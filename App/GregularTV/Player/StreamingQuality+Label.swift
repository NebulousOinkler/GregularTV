import GregularCore

extension StreamingQuality {
    /// How Settings names each option. The resolutions are what Jellyfin
    /// typically picks for a video at that bitrate, so they're approximate.
    /// (Kept in the app: another app, such as radio, would name them its own way.)
    var label: String {
        switch self {
        case .auto: "Auto"
        case .maximum: "Maximum (original quality)"
        case .hd20: "1080p · 20 Mbps"
        case .hd10: "1080p · 10 Mbps"
        case .hd720: "720p · 4 Mbps"
        case .sd: "480p · 1.5 Mbps"
        }
    }
}
