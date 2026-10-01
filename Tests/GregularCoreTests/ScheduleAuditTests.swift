import Foundation
import Testing
@testable import GregularCore

/// The schedule audit: statistics on the shuffle and a simulated month on
/// every channel, printed as `AUDIT` lines. About 25 seconds, so it only runs
/// when asked: `SCHEDULE_AUDIT=1 swift test --filter ScheduleAudit`.
@Suite(.serialized, .timeLimit(.minutes(1)),
       .enabled(if: ProcessInfo.processInfo.environment["SCHEDULE_AUDIT"] != nil))
struct ScheduleAudit {
    // MARK: Statistics

    /// Chi-square survival function (Wilson–Hilferty), good for df ≥ 3.
    static func pValue(chiSquare x: Double, df: Int) -> Double {
        let k = Double(df)
        let z = (pow(x / k, 1.0 / 3) - (1 - 2 / (9 * k))) / sqrt(2 / (9 * k))
        return 0.5 * erfc(z / 2.squareRoot())
    }

    static func chiSquare(_ counts: [Int], expected: Double) -> Double {
        counts.map { pow(Double($0) - expected, 2) / expected }.reduce(0, +)
    }

    static func codes(_ n: Int, salt: UInt64 = 1) -> [ScheduleCode] {
        var rng = SeededRandom(seed: 0xC0DE ^ salt)
        return (0..<n).map { _ in ScheduleCode(value: rng.next() >> 14)! }
    }

    static func line(_ s: String) { print("AUDIT " + s) }

    // MARK: 1. Every order equally likely, through the real path (code → key → pass shuffle)

    @Test func everyOrderEquallyLikely() {
        for n in 2...7 {
            let orders = (1...n).reduce(1, *)
            let samples = orders * (n <= 6 ? 100 : 20)
            var counts: [[Int]: Int] = [:]
            // Through the same path a channel uses: code → channel key → pass → shuffle.
            for (i, code) in Self.codes(samples, salt: UInt64(n)).enumerated() {
                let passes = ShuffledOrder.Passes(count: n, seed: code.key(forChannelSeed: 1))
                let pass = i % 1000   // passes far apart and near the epoch alike
                counts[(0..<n).map { passes.index(at: pass * n + $0) }, default: 0] += 1
            }
            let all = (0..<orders).map { _ in 0 }   // pad so unseen orders count as 0
            let values = Array(counts.values) + all.prefix(orders - counts.count)
            let x = Self.chiSquare(values, expected: Double(samples) / Double(orders))
            Self.line(String(format: "orders n=%d: %d of %d orders seen, %d samples, each %d…%d (expected %.0f), chi2/df=%.3f, p=%.3f",
                             n, counts.count, orders, samples, values.min()!, values.max()!,
                             Double(samples) / Double(orders), x / Double(orders - 1),
                             Self.pValue(chiSquare: x, df: orders - 1)))
        }
    }

    @Test func feistelSizesAreEven() {
        for n in [11, 12, 13, 16, 17, 20, 33, 65, 100] {
            let samples = n <= 13 ? 30_000 : 20_000
            var table = [Int](repeating: 0, count: n * n)       // position × item
            var pairs = [Int](repeating: 0, count: n * n)       // item at p, item at p+1
            var triples: [Int: Int] = [:]                       // first three, n ≤ 13
            for (i, code) in Self.codes(samples, salt: UInt64(n) &* 77).enumerated() {
                let passes = ShuffledOrder.Passes(count: n, seed: code.key(forChannelSeed: 3))
                let base = (i % 500) * n
                let order = (0..<n).map { passes.index(at: base + $0) }
                for p in 0..<n { table[p * n + order[p]] += 1 }
                for p in 0..<(n - 1) { pairs[order[p] * n + order[p + 1]] += 1 }
                if n <= 13 { triples[(order[0] * n + order[1]) * n + order[2], default: 0] += 1 }
            }
            let xPos = Self.chiSquare(table, expected: Double(samples) / Double(n))
            let offDiagonal = pairs.enumerated().filter { $0.offset / n != $0.offset % n }.map(\.element)
            let xPair = Self.chiSquare(offDiagonal, expected: Double(samples * (n - 1)) / Double(n * (n - 1)))
            var report = String(format: "feistel n=%d (%d samples): position×item chi2/df=%.3f p=%.3f; neighbours chi2/df=%.3f p=%.3f",
                                n, samples, xPos / Double((n - 1) * (n - 1)), Self.pValue(chiSquare: xPos, df: (n - 1) * (n - 1)),
                                xPair / Double(n * (n - 1) - 1), Self.pValue(chiSquare: xPair, df: n * (n - 1) - 1))
            if n <= 13 {
                let cells = n * (n - 1) * (n - 2)
                let values = Array(triples.values) + [Int](repeating: 0, count: cells - triples.count)
                let x = Self.chiSquare(values, expected: Double(samples) / Double(cells))
                report += String(format: "; first three chi2/df=%.3f p=%.3f", x / Double(cells - 1),
                                 Self.pValue(chiSquare: x, df: cells - 1))
            }
            Self.line(report)
        }
    }

    @Test func passesAreIndependent() {
        // n = 4: the order of one pass and the next, 24 × 24 combinations.
        let n = 4, samples = 576 * 50
        var counts: [Int: Int] = [:]
        func id(_ o: [Int]) -> Int { o.reduce(0) { $0 * 4 + $1 } }
        for (i, code) in Self.codes(samples, salt: 99).enumerated() {
            let passes = ShuffledOrder.Passes(count: n, seed: code.key(forChannelSeed: 5))
            let pass = i % 700
            let a = (0..<n).map { passes.index(at: pass * n + $0) }
            let b = (0..<n).map { passes.index(at: (pass + 1) * n + $0) }
            counts[id(a) * 1000 + id(b), default: 0] += 1
        }
        let values = Array(counts.values) + [Int](repeating: 0, count: 576 - counts.count)
        let x = Self.chiSquare(values, expected: Double(samples) / 576)
        Self.line(String(format: "consecutive passes n=4: %d of 576 pairs seen, chi2/df=%.3f p=%.3f",
                         counts.count, x / 575, Self.pValue(chiSquare: x, df: 575)))
    }

    // MARK: 2. Through the strategy and the engine

    static func show(_ name: String, episodes: Int, minutes: Double, genres: [String] = []) -> [MediaItem] {
        (1...episodes).map { e in
            MediaItem(id: "\(name)-\(e)", kind: .episode, name: "\(name) \(e)", duration: minutes * 60,
                      seriesID: "id-\(name)", seriesName: name, seasonNumber: 1, episodeNumber: e, genres: genres)
        }
    }

    @Test func strategyPassesEveryOrderEquallyLikely() {
        // ShuffledShows itself: a whole pass of 5 shows, pass-aligned.
        let n = 5
        let items = (0..<n).flatMap { Self.show("S\($0)", episodes: 30, minutes: 22) }
        var counts: [[String]: Int] = [:]
        let samples = 120 * 60
        for (i, code) in Self.codes(samples, salt: 7).enumerated() {
            let key = code.key(forChannelSeed: 1)
            let content = ChannelContent(items: items, seed: key)
            let stream = ShuffledShows().programmes(from: content, startingAt: (i % 400) * n, rng: SeededRandom(seed: key))
            counts[(0..<n).map { _ in stream.next()!.seriesName! }, default: 0] += 1
        }
        let x = Self.chiSquare(Array(counts.values), expected: Double(samples) / 120)
        Self.line(String(format: "ShuffledShows n=5: %d of 120 orders, chi2/df=%.3f p=%.3f",
                         counts.count, x / 119, Self.pValue(chiSquare: x, df: 119)))
    }

    @Test func engineMarginalIsEven() {
        // What a channel of 6 shows airs at one moment, over many codes: each show 1/6.
        let n = 6
        let items = (0..<n).flatMap { Self.show("S\($0)", episodes: 20, minutes: 22) }
        let channel = Channel(number: 1, name: "T", itemTypes: [.episode], source: AllItemsSource(),
                              strategyID: ShuffledShows.id, seed: 1, padToMinutes: 30)
        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        var at = [String: Int](), pairs = [String: Int]()
        let samples = 1_200
        for code in Self.codes(samples, salt: 11) {
            let schedule = ChannelSchedule(channel: channel, items: items, code: code)!
            let a = schedule.programme(at: moment).item.seriesName!
            let b = schedule.programme(at: moment.addingTimeInterval(1800)).item.seriesName!
            at[a, default: 0] += 1
            pairs[a + b, default: 0] += 1
        }
        let x = Self.chiSquare(Array(at.values), expected: Double(samples) / Double(n))
        let same = pairs.filter { $0.key.prefix(2) == $0.key.suffix(2) }.values.reduce(0, +)
        Self.line(String(format: "engine n=6 at one moment: %@ chi2/df=%.3f p=%.3f; same show next slot %.2f%% (theory 1/n² = %.2f%%)",
                         at.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                         x / 5, Self.pValue(chiSquare: x, df: 5),
                         100 * Double(same) / Double(samples), 100.0 / Double(n * n)))
    }

    // MARK: 3. A realistic library, a month on every bundled channel

    /// A made-up library: `seriesCount` series and `filmCount` films, with
    /// typical lengths and TMDB's genre names.
    static func realisticLibrary(seriesCount: Int = 90, filmCount: Int = 450) -> (programmes: [MediaItem], commercials: [MediaItem]) {
        var rng = SeededRandom(seed: 2026)
        let tvGenres = ["Comedy", "Drama", "Animation", "Sci-Fi & Fantasy", "Family", "Kids", "Documentary", "Reality",
                        "Crime", "Mystery", "Action & Adventure", "Food", "Talk"]
        let filmGenres = ["Comedy", "Drama", "Animation", "Science Fiction", "Family", "Documentary", "Action", "Adventure",
                          "Horror", "Thriller", "Crime", "Romance", "Fantasy", "Mystery", "Western", "War"]
        let showMinutes: [Double] = [11, 21.5, 22, 23, 24, 25, 26, 28, 29.5, 30.2, 33, 42, 44, 46, 50, 58, 61]
        var items: [MediaItem] = []
        for s in 0..<seriesCount {
            let minutes = showMinutes[rng.int(below: showMinutes.count)]
            let episodes = [6, 10, 13, 22, 40, 66, 100, 180, 250][rng.int(below: 9)]
            let genres = (0..<(1 + rng.int(below: 2))).map { _ in tvGenres[rng.int(below: tvGenres.count)] }
            items += (1...episodes).map { e in
                MediaItem(id: "show\(s)-\(e)", kind: .episode, name: "Show \(s) \(e)",
                          duration: minutes * 60 + Double(rng.int(below: 90)) - 45,
                          seriesID: "show\(s)", seriesName: "Show \(s)", seasonNumber: 1 + e / 20, episodeNumber: e % 20,
                          genres: genres)
            }
        }
        for m in 0..<filmCount {
            let genres = (0..<(1 + rng.int(below: 3))).map { _ in filmGenres[rng.int(below: filmGenres.count)] }
            items.append(MediaItem(id: "movie\(m)", kind: .movie, name: "Movie \(m)",
                                   duration: Double(78 + rng.int(below: 95)) * 60 + Double(rng.int(below: 60)),
                                   productionYear: 1935 + rng.int(below: 90), genres: genres))
        }
        let clips = (0..<150).map { c in
            MediaItem(id: "ad\(c)", kind: .video, name: "Ad \(c)", duration: Double([15, 30, 30, 30, 60, 60, 90, 120][rng.int(below: 8)]))
        }
        return (items, clips)
    }

    @Test(arguments: [(90, 450), (25, 120)])
    func aMonthOnEveryChannel(seriesCount: Int, filmCount: Int) throws {
        let (library, clips) = Self.realisticLibrary(seriesCount: seriesCount, filmCount: filmCount)
        let lineup = try ChannelLineup.bundled()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let end = start.addingTimeInterval(30 * 86_400)
        Self.line("— library: \(seriesCount) series, \(filmCount) films")
        let schedules = lineup.schedules(for: library, fillerPool: clips, code: ScheduleCode("7KQM2-X9PDA")!)
        let shown = Set(schedules.map(\.channel.number))
        for channel in lineup.channels where !shown.contains(channel.number) {
            let matching = library.filter(channel.accepts)
            Self.line(String(format: "ch%2d %-24@ HIDDEN: %d series, %d films match", channel.number, channel.name as NSString,
                             Set(matching.compactMap(\.seriesID)).count, matching.filter { $0.kind == .movie }.count))
        }
        for schedule in schedules {
            let programmes = schedule.programmes(from: start, to: end).filter { $0.start >= start }
            let series = schedule.content.series.filter { !ShuffledMix.isFilm($0) }.count
            let films = schedule.content.series.count - series
            let filmTime = programmes.filter { $0.item.kind == .movie }.map { $0.slotEnd.timeIntervalSince($0.start) }.reduce(0, +)
            let allTime = programmes.map { $0.slotEnd.timeIntervalSince($0.start) }.reduce(0, +)
            var lastItem: [String: Date] = [:], lastSeries: [String: Date] = [:]
            var sameItemDay = 0, seriesTwiceIn3h = 0, seriesAirings = 0
            for p in programmes {
                if let t = lastItem[p.item.id], p.start.timeIntervalSince(t) < 86_400 { sameItemDay += 1 }
                if p.item.kind == .episode {
                    seriesAirings += 1
                    if let t = lastSeries[p.item.seriesKey], p.start.timeIntervalSince(t) < 3 * 3600 { seriesTwiceIn3h += 1 }
                    lastSeries[p.item.seriesKey] = p.start
                }
                lastItem[p.item.id] = p.start
            }
            let distinctPerDay = Double(Set(programmes.map(\.item.seriesKey)).count)
            Self.line(String(format: "ch%2d %-24@ %3d series %4d films | films %2.0f%% of airtime (asked %@) | %4.1f programmes/day, %3.0f titles seen in 30 days | same item within 24 h: %d | a series again within 3 h: %.1f%% of its airings",
                             schedule.channel.number, schedule.channel.name as NSString, series, films,
                             100 * filmTime / allTime, schedule.channel.filmShare.map { String(format: "%.0f%%", 100 * $0) } ?? "–",
                             Double(programmes.count) / 30, distinctPerDay, sameItemDay,
                             seriesAirings == 0 ? 0 : 100 * Double(seriesTwiceIn3h) / Double(seriesAirings)))
        }
    }
}

extension ScheduleAudit {
    @Test func runBoundaries() throws {
        let (library, clips) = Self.realisticLibrary()
        let lineup = try ChannelLineup.bundled()
        let code = ScheduleCode("7KQM2-X9PDA")!
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; f.timeZone = ChannelSchedule.dayTimeZone
        for schedule in lineup.schedules(for: library, fillerPool: clips, code: code)
        where [1, 10, 14].contains(schedule.channel.number) {
            let programmes = schedule.programmes(from: start, to: start.addingTimeInterval(4 * 86_400)).filter { $0.start >= start }
            Self.line("— ch\(schedule.channel.number) run \(schedule.run(containing: start).duration / 3600) h")
            var seen: [String: Date] = [:]
            for p in programmes {
                let gap = p.slotEnd.timeIntervalSince(p.start) - p.item.duration
                let again = seen[p.item.id].map { String(format: " SAME ITEM %.1f h ago", p.start.timeIntervalSince($0) / 3600) } ?? ""
                if gap > 30 * 60 || !again.isEmpty || f.string(from: p.start).hasSuffix("23:30") || f.string(from: p.start).hasPrefix("") && Calendar(identifier: .gregorian).dateComponents(in: ChannelSchedule.dayTimeZone, from: p.start).hour! >= 21 {
                    Self.line(String(format: "%@ %@ (%.0f min) break %.0f min%@", f.string(from: p.start), p.item.name, p.item.duration / 60, gap / 60, again))
                }
                seen[p.item.id] = p.start
            }
        }
    }
}

extension ScheduleAudit {
    @Test func whereRepeatsHappen() throws {
        let (library, clips) = Self.realisticLibrary()
        let lineup = try ChannelLineup.bundled()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for code in Self.codes(3, salt: 5) {
            for schedule in lineup.schedules(for: library, fillerPool: clips, code: code) {
                let programmes = schedule.programmes(from: start, to: start.addingTimeInterval(30 * 86_400)).filter { $0.start >= start }
                var lastShow: [String: Int] = [:], lastItem: [String: Date] = [:]
                var quick: [Double] = [], sameItem: [Double] = []
                for (i, p) in programmes.enumerated() {
                    // Hours from this slot to the nearest run boundary (midnight Pacific), wrapped to ±12.
                    let run = schedule.run(containing: p.start)
                    var h = p.start.timeIntervalSince(run.start) / 3600
                    if h > 12 { h -= run.duration / 3600 }
                    if let j = lastShow[p.item.seriesKey], i - j <= 6 { quick.append(h) }
                    if let t = lastItem[p.item.id], p.start.timeIntervalSince(t) < 86_400 { sameItem.append(h) }
                    lastShow[p.item.seriesKey] = i
                    lastItem[p.item.id] = p.start
                }
                let nearBoundary = quick.filter { abs($0) <= 6 }.count
                Self.line(String(format: "%@ ch%2d slots=%4d show again within 6 slots: %3d (%3d within 6 h of the run boundary) | same item within 24 h: %d, hours from boundary %@",
                                 code.description, schedule.channel.number, programmes.count, quick.count, nearBoundary, sameItem.count,
                                 sameItem.map { String(format: "%+.1f", $0) }.joined(separator: " ")))
            }
        }
    }
}
