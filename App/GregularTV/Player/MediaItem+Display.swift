import GregularCore

extension MediaItem {
    /// The series name for episodes, the title for movies.
    var displayTitle: String {
        seriesName ?? name
    }

    /// "S2 E30 · Climax" for episodes, "1999" for movies.
    var displaySubtitle: String? {
        switch kind {
        case .episode:
            let number = [seasonNumber.map { "S\($0)" }, episodeNumber.map { "E\($0)" }]
                .compactMap { $0 }.joined(separator: " ")
            return [number, name].filter { !$0.isEmpty }.joined(separator: " · ")
        case .movie:
            return productionYear.map(String.init)
        case .video:
            return nil
        }
    }
}
