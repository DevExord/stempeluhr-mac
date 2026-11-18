// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum Fmt {
    /// Compact `H:MM` for the menu bar (stable width, updates each minute).
    static func hm(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// Full `H:MM:SS` ticking clock for the popover.
    static func hms(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// `HH:mm` wall-clock time in the local zone.
    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Relative-ish "as of" label for an unconfirmed state.
    static func asOf(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    static func label(_ ref: KimaiRef) -> String {
        ref.name ?? "#\(ref.id)"
    }
}
