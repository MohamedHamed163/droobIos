import Foundation

/// Display + parse helpers for the 6-character study-room join code.
///
/// Wire form is `9F42K7` (no separator). UI form is `9F4-2K7` (hyphen
/// at the midpoint) to mirror the figma and match how people verbally
/// share codes ("nine-eff-four, dash, two-kay-seven"). All inbound
/// strings are normalised so the server sees a single canonical form.
enum JoinCodeFormat {

    /// Insert the visual hyphen at the midpoint. Pass-through if the
    /// input isn't 6 chars (e.g. while the user is still typing).
    static func display(_ raw: String) -> String {
        let stripped = strip(raw)
        guard stripped.count == 6 else { return stripped }
        let i = stripped.index(stripped.startIndex, offsetBy: 3)
        return stripped[..<i] + "-" + stripped[i...]
    }

    /// Normalise on input — uppercase, strip every non-alphanumeric so
    /// the server's lookup matches whether the user typed `9F4-2K7`,
    /// `9f42k7`, or `9F4 2K7`.
    static func strip(_ raw: String) -> String {
        let chars = raw.unicodeScalars.filter {
            ("A"..."Z").contains(Character($0)) ||
            ("a"..."z").contains(Character($0)) ||
            ("0"..."9").contains(Character($0))
        }
        return String(String.UnicodeScalarView(chars)).uppercased()
    }
}
