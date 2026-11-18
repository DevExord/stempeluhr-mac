// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Parsing and formatting of Kimai's timestamps, mirroring the original app's
/// `core/src/kimai/time.rs`.
enum KimaiTime {
    /// Parses Kimai timestamps. PHP's `O` format yields offsets without a
    /// colon (`2024-05-01T10:00:00+0200`), which strict ISO parsers reject, so
    /// a colon is inserted first. `Z` and `+02:00` are also accepted. A naive
    /// time (no offset) is rejected, like the original.
    static func parse(_ raw: String) throws -> Date {
        let s = fixOffset(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if let d = isoFractional.date(from: s) { return d }
        if let d = iso.date(from: s) { return d }
        throw KimaiError.unexpectedResponse("invalid timestamp \"\(raw)\"")
    }

    /// Turns a trailing `+HHMM` / `-HHMM` into `+HH:MM` so the ISO parser
    /// accepts it. Leaves `Z` and already-colonned offsets untouched.
    static func fixOffset(_ s: String) -> String {
        guard let tRange = s.range(of: "T") else { return s }
        let tail = s[tRange.lowerBound...]
        // Find the last + or - (the offset sign) in the time portion.
        guard let signIdx = tail.lastIndex(where: { $0 == "+" || $0 == "-" }) else { return s }
        let off = tail[tail.index(after: signIdx)...]
        if off.count == 4, off.allSatisfy({ $0.isNumber }) {
            let hh = off.prefix(2)
            let mm = off.suffix(2)
            return String(s[..<signIdx]) + String(s[signIdx]) + "\(hh):\(mm)"
        }
        return s
    }

    /// Formats an instant as the naive local time Kimai expects for `begin`,
    /// interpreted in the user's configured time zone.
    static func formatBegin(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
