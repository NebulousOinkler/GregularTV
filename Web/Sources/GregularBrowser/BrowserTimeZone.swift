import Foundation
import JavaScriptKit

/// The viewer's time zone. Foundation has no system to ask on WebAssembly,
/// so it takes GMT, and every time on screen (the clock, the guide, when a
/// programme starts) would be off by the viewer's offset. The browser
/// knows; this hands it to Foundation as `TZ`, which Foundation reads first.
public enum BrowserTimeZone {
    /// The browser's time zone, such as "America/Los_Angeles".
    public static var browser: String? {
        guard let format = JSObject.global.Intl.object?.DateTimeFormat.function?.new() else { return nil }
        return format.resolvedOptions!().object?.timeZone.string
    }

    /// Makes `identifier` (the browser's, unless told) Foundation's current
    /// time zone. Call before anything is shown. One Foundation doesn't know
    /// is left alone.
    public static func adopt(_ identifier: String? = browser) {
        guard let identifier, TimeZone(identifier: identifier) != nil else { return }
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
    }
}
