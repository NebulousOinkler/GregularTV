/// What can be typed where a schedule code goes: a schedule code, or a
/// special mode's keyword. A schedule code always reads as one, so no
/// keyword may be one (`SpecialModeRegistry.keywordHash(for:)` turns them down).
public enum CodeEntry: Sendable, Hashable {
    case schedule(ScheduleCode)
    case specialMode(SpecialMode)

    /// Nil if `text` is neither a schedule code nor a keyword in `specialModes`.
    public init?(_ text: String, specialModes: SpecialModeRegistry) {
        if let code = ScheduleCode(text) {
            self = .schedule(code)
        } else if let mode = specialModes.mode(forKeyword: text) {
            self = .specialMode(mode)
        } else {
            return nil
        }
    }
}
