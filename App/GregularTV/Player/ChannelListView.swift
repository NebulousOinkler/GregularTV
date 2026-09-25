import GregularCore
import SwiftUI

/// The channel selector: every channel with what's on now, or, in a break,
/// what's up next. Opened from `RemoteControls.watching` (Left, as shipped).
/// Select tunes. The buttons in `RemoteControls.channelList` (Right or Menu
/// to close, as shipped), or 15 s without activity, close it and stay on the
/// current channel.
struct ChannelListView: View {
    static let idleTimeout: Duration = .seconds(15)

    let channels: [ChannelSchedule]
    let currentNumber: Int
    let onSelect: (Int) -> Void
    /// Buttons from `RemoteControls.channelList`, and `.close` when idle.
    let onRemote: (RemoteAction) -> Void

    @FocusState private var focusedNumber: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: rows are only built as they scroll into view, so any
                    // number of channels is fine.
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(channels, id: \.channel.number) { schedule in
                            Button { onSelect(schedule.channel.number) } label: {
                                ChannelRow(schedule: schedule, date: context.date,
                                           isCurrent: schedule.channel.number == currentNumber)
                            }
                            .focused($focusedNumber, equals: schedule.channel.number)
                            .id(schedule.channel.number)
                        }
                    }
                    .padding(40)
                }
                // Start on the channel being watched, and keep focus inside the list.
                .defaultFocus($focusedNumber, currentNumber)
                .focusSection()
                // Handled here, on the rows' container, so presses reach them from the focused row.
                .remoteControls(RemoteControls.channelList, perform: onRemote)
                .task {
                    // Scroll the current channel's row into existence, then focus it.
                    proxy.scrollTo(currentNumber, anchor: .center)
                    try? await Task.sleep(for: .milliseconds(100))
                    focusedNumber = currentNumber
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Text(RemoteControls.hint(for: RemoteControls.channelList))
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 40).padding(.top, 30)
        }
        .frame(width: 820)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .closeWhenIdle(after: Self.idleTimeout, activity: focusedNumber) { onRemote(.close) }
    }
}

private struct ChannelRow: View {
    let schedule: ChannelSchedule
    let date: Date
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Text(schedule.channel.number, format: .number)
                .font(.title2.monospacedDigit()).bold()
                .lineLimit(1).fixedSize()
                .frame(width: 80, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(schedule.channel.name).font(.headline)
                    if isCurrent { Image(systemName: "play.fill").font(.caption) }
                }
                switch schedule.nowShowing(at: date) {
                case .programme(let airing):
                    Text(airing.item.displayTitle).font(.body).lineLimit(1)
                    RowProgressBar(fraction: fraction(from: airing.start, to: airing.end))
                    Text("until \(airing.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                case .inBreak(let ended, let next):
                    // The programme is over: say what's next, not what ended.
                    Text("Up next: \(next.item.displayTitle)").font(.body).lineLimit(1)
                    RowProgressBar(fraction: fraction(from: ended.end, to: next.start)).opacity(0.45)
                    HStack(spacing: 6) {
                        BreakStyle.label
                        Text("· starts \(next.start.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fraction(from start: Date, to end: Date) -> Double {
        guard end > start else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}

/// A plain progress bar in solid colours: white on a row, dark on the
/// highlighted (white) row. The system `ProgressView` restyled its
/// translucent track as each row gained and lost focus, which flashed while
/// scrolling; this changes colour once, with no animation.
private struct RowProgressBar: View {
    let fraction: Double
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let ink = isFocused ? Color.black.opacity(0.8) : Color.white
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.2))
                Capsule().fill(ink).frame(width: max(geometry.size.width * fraction, 6))
            }
        }
        .frame(height: 6)
        .padding(.vertical, 4)
        .transaction { $0.animation = nil }
    }
}
