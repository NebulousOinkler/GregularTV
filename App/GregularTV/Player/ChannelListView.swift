import GregularTVCore
import SwiftUI

/// The channel selector: every channel with what's on now. Opened by pressing
/// left while watching. Select tunes. Right, Menu, or 15 s without activity
/// closes it and stays on the current channel.
struct ChannelListView: View {
    static let idleTimeout: Duration = .seconds(15)

    let channels: [ChannelSchedule]
    let currentNumber: Int
    let onSelect: (Int) -> Void
    let onClose: () -> Void

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
                .onExitCommand(perform: onClose)
                .onMoveCommand { direction in
                    if direction == .right { onClose() }   // left opened it; right puts it away
                }
                .task {
                    // Scroll the current channel's row into existence, then focus it.
                    proxy.scrollTo(currentNumber, anchor: .center)
                    try? await Task.sleep(for: .milliseconds(100))
                    focusedNumber = currentNumber
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Text("▶ or Menu to close")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 40).padding(.top, 30)
        }
        .frame(width: 820)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .closeWhenIdle(after: Self.idleTimeout, activity: focusedNumber, perform: onClose)
    }
}

private struct ChannelRow: View {
    let schedule: ChannelSchedule
    let date: Date
    let isCurrent: Bool

    var body: some View {
        let airing = schedule.programme(at: date)
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
                Text(airing.item.displayTitle).font(.body).lineLimit(1)
                ProgressView(value: min(1, max(0, date.timeIntervalSince(airing.start) / airing.item.duration)))
                Text("until \(airing.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
