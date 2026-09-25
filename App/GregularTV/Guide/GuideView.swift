import GregularCore
import GregularScreens
import SwiftUI

/// The programme guide: channels down the side, from the current half hour
/// to at least six hours ahead, with the focused programme's details above.
/// Three hours fit on screen; the grid scrolls sideways as focus moves, with
/// the channel names pinned on the left and the times pinned along the top.
/// Each block's break (commercials or blank airtime after the programme) is a
/// darker tail at its right edge.
/// Opened from watching with `RemoteControls.watching` (Menu, as shipped).
/// Select tunes to the channel. The buttons in `RemoteControls.guide` act on
/// it: as shipped, Play/Pause opens Settings, and Menu steps back, first to
/// the Settings button, then back to the programme playing. 60 s without
/// activity closes it and stays on the current channel.
struct GuideView: View {
    static let idleTimeout: Duration = .seconds(60)

    let channels: [ChannelSchedule]
    let currentNumber: Int
    let onSelect: (Int) -> Void
    /// Buttons from `RemoteControls.guide`, the Settings button, and `.close` when idle.
    let onRemote: (RemoteAction) -> Void

    static let channelColumnWidth: CGFloat = 330
    /// Three hours fill the visible grid.
    static let hourWidth: CGFloat = 1390 / 3
    static let rowHeight: CGFloat = 96
    static let rowSpacing: CGFloat = 8

    static func trackWidth(_ window: GuideWindow) -> CGFloat {
        CGFloat(window.duration / 3600) * hourWidth
    }

    @FocusState private var focusedID: String?
    /// Where the grid's top-left corner is, relative to what's on screen: it
    /// goes negative as the grid scrolls. The ruler and channel names follow it.
    @State private var gridOrigin: CGPoint = .zero

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let window = GuideWindow(containing: context.date)
            let startFocus = nowID(channel: currentNumber, window: window, at: context.date)

            VStack(alignment: .leading, spacing: 24) {
                header(window: window, now: context.date)
                // The ruler and channel names are much bigger than the screen.
                // Each is drawn over space the layout sets aside, following the
                // grid's scroll position, so they never change the guide's size.
                Color.clear
                    .frame(height: TimeRuler.height)
                    .overlay(alignment: .leading) { TimeRuler(window: window).offset(x: gridOrigin.x) }
                    .clipped()
                    .padding(.leading, Self.channelColumnWidth)
                HStack(alignment: .top, spacing: 0) {
                    Color.clear
                        .frame(width: Self.channelColumnWidth)
                        .overlay(alignment: .top) {
                            ChannelColumn(channels: channels, currentNumber: currentNumber).offset(y: gridOrigin.y)
                        }
                        .clipped()
                    grid(window: window, now: context.date, startFocus: startFocus)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 50)
            .remoteControls(RemoteControls.guide) { action in
                if action == .stepBack { stepBack() } else { onRemote(action) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.88))
        .closeWhenIdle(after: Self.idleTimeout, activity: focusedID) { onRemote(.close) }
    }

    /// The programmes, scrolling both ways. Focus moving off the edge scrolls it.
    private func grid(window: GuideWindow, now: Date, startFocus: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                // Lazy: rows (and their programmes) are only worked out as they
                // scroll into view, so any number of channels is fine.
                LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(channels, id: \.channel.number) { schedule in
                        GuideRow(schedule: schedule, window: window, focusedID: $focusedID, onSelect: onSelect)
                            .id(schedule.channel.number)
                    }
                }
                .overlay(alignment: .topLeading) { NowLine(window: window, date: now) }
                .background {   // for tvOS 17 (see `ReportsContentOrigin`)
                    GeometryReader { geometry in
                        Color.clear.preference(key: ContentOriginKey.self,
                                               value: geometry.frame(in: .named(ContentOriginKey.space)).origin)
                    }
                }
            }
            .coordinateSpace(name: ContentOriginKey.space)
            .scrollIndicators(.hidden)
            .clipped()   // tvOS doesn't clip scroll views; keep programmes off the channel names
            .modifier(ReportsContentOrigin(origin: $gridOrigin))
            .defaultFocus($focusedID, startFocus)
            .task {
                // Scroll the current channel's row into existence, at the start
                // of the window, then focus what's on now there.
                proxy.scrollTo(currentNumber, anchor: .leading)
                try? await Task.sleep(for: .milliseconds(100))
                focusedID = startFocus
            }
        }
    }

    /// Focus ID of the Settings button.
    static let settingsFocusID = "settings"


    /// Menu, as shipped: from a programme up to the Settings button
    /// (highlighted, not pressed), and from there back to the programme playing.
    private func stepBack() {
        if focusedID == Self.settingsFocusID {
            onRemote(.close)
        } else {
            focusedID = Self.settingsFocusID
        }
    }

    static func id(_ schedule: ChannelSchedule, _ cell: GuideCell) -> String {
        "\(schedule.channel.number)|\(cell.id)"
    }

    private func schedule(number: Int) -> ChannelSchedule? {
        channels.first { $0.channel.number == number }
    }

    /// Focus ID of what's on now on `channel`.
    private func nowID(channel: Int, window: GuideWindow, at date: Date) -> String? {
        schedule(number: channel).flatMap { schedule in
            window.cells(for: schedule).first { $0.contains(date) }.map { Self.id(schedule, $0) }
        }
    }

    /// Details of the focused programme, with the Settings button on the right.
    /// Only the focused channel's programmes are looked up.
    private func header(window: GuideWindow, now: Date) -> some View {
        let number = focusedID?.split(separator: "|").first.flatMap { Int($0) }
        let focused = number.flatMap(schedule(number:)).flatMap { schedule in
            window.cells(for: schedule).first { Self.id(schedule, $0) == focusedID }.map { (schedule, $0) }
        }

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                if let (schedule, cell) = focused {
                    // In its break, said on the channel line, so the header
                    // keeps its three lines and never reaches the time ruler.
                    HStack(spacing: 6) {
                        Text("\(schedule.channel.number) · \(schedule.channel.name)")
                        if let span = cell.breakSpan, span.start <= now, now < span.end {
                            Text("· Programme ended ·")
                            BreakStyle.label
                            Text("until \(span.end.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    .font(.headline).foregroundStyle(.secondary).lineLimit(1)
                    Text(cell.programme.item.displayTitle).font(.title2).bold().lineLimit(1)
                    Text([cell.programme.item.displaySubtitle,
                          "\(cell.programme.start.formatted(date: .omitted, time: .shortened)) – \(cell.programme.end.formatted(date: .omitted, time: .shortened))"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.headline).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Guide").font(.title2).bold()
                }
            }
            .frame(height: 170, alignment: .top)
            Spacer()
            VStack(alignment: .trailing, spacing: 12) {
                Button { onRemote(.openSettings) } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .focused($focusedID, equals: Self.settingsFocusID)
                Text(RemoteControls.hint(for: RemoteControls.guide))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        // A focus section: pressing Up from the top row reaches Settings
        // from anywhere across the grid, not just from below the button.
        .focusSection()
    }
}

/// Keeps `origin` up to date with where a scroll view's content is: (0, 0)
/// at rest, going negative as it scrolls right and down.
private struct ReportsContentOrigin: ViewModifier {
    @Binding var origin: CGPoint

    func body(content: Content) -> some View {
        if #available(tvOS 18, *) {
            content.onScrollGeometryChange(for: CGPoint.self) { geometry in
                CGPoint(x: -(geometry.contentOffset.x + geometry.contentInsets.leading),
                        y: -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, new in
                origin = new
            }
        } else {
            content.onPreferenceChange(ContentOriginKey.self) { new in
                MainActor.assumeIsolated { origin = new }
            }
        }
    }
}

/// tvOS 17 only: the content's origin, reported from inside the scroll view,
/// since `onScrollGeometryChange` is tvOS 18+.
private struct ContentOriginKey: PreferenceKey {
    static let space = "guideGrid"
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Channel numbers and names, one per row, lined up with the grid.
private struct ChannelColumn: View {
    let channels: [ChannelSchedule]
    let currentNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: GuideView.rowSpacing) {
            ForEach(channels, id: \.channel.number) { schedule in
                HStack(spacing: 12) {
                    Text(schedule.channel.number, format: .number)
                        .font(.title3.monospacedDigit()).bold()
                        .lineLimit(1).fixedSize()
                        .frame(width: 70, alignment: .trailing)
                    Text(schedule.channel.name).font(.callout).lineLimit(2).minimumScaleFactor(0.8)
                    if schedule.channel.number == currentNumber { Image(systemName: "play.fill").font(.caption) }
                }
                .frame(width: GuideView.channelColumnWidth, height: GuideView.rowHeight, alignment: .leading)
            }
        }
    }
}

/// One channel's programmes, as blocks sized by time.
private struct GuideRow: View {
    let schedule: ChannelSchedule
    let window: GuideWindow
    var focusedID: FocusState<String?>.Binding
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(window.cells(for: schedule)) { cell in
                Button { onSelect(schedule.channel.number) } label: {
                    GuideCellLabel(cell: cell, width: width(of: cell))
                }
                .buttonStyle(GuideCellStyle())
                .frame(width: width(of: cell))
                .focused(focusedID, equals: GuideView.id(schedule, cell))
            }
        }
        .frame(width: GuideView.trackWidth(window), height: GuideView.rowHeight, alignment: .leading)
    }

    private func width(of cell: GuideCell) -> CGFloat {
        CGFloat(cell.visibleEnd.timeIntervalSince(cell.visibleStart) / window.duration) * GuideView.trackWidth(window)
    }
}

private struct GuideCellLabel: View {
    let cell: GuideCell
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((cell.startsBeforeWindow ? "◀ " : "") + cell.programme.item.displayTitle)
                .font(.callout).bold().lineLimit(1)
            if width >= 110 {   // too narrow to fit a time legibly
                Text(cell.programme.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        // The break after the programme: a darker tail, no text (it's usually narrow).
        .background(alignment: .trailing) {
            if cell.breakFraction > 0 {
                BreakStyle.guideTail.frame(width: width * cell.breakFraction)
            }
        }
    }
}

/// A flat block that turns white when focused. The default tvOS button style
/// grows on focus and would overlap its neighbours in a tight grid.
private struct GuideCellStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? .black : .white)
            .background(isFocused ? Color.white : Color.white.opacity(configuration.isPressed ? 0.3 : 0.12),
                        in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))   // the break's tail too
            .padding(3)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// Times along the top: 3:00 PM, 3:30 PM, and so on.
private struct TimeRuler: View {
    static let height: CGFloat = 40
    let window: GuideWindow

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(window.timeMarks, id: \.self) { mark in
                Text(mark.formatted(date: .omitted, time: .shortened))
                    .font(.callout).foregroundStyle(.secondary)
                    .offset(x: window.fraction(of: mark) * GuideView.trackWidth(window))
            }
        }
        .frame(width: GuideView.trackWidth(window), height: Self.height, alignment: .leading)
    }
}

/// A thin line marking the current time across every row.
private struct NowLine: View {
    let window: GuideWindow
    let date: Date

    var body: some View {
        Rectangle()
            .fill(.yellow)
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .offset(x: window.fraction(of: date) * GuideView.trackWidth(window))
            .allowsHitTesting(false)
    }
}
