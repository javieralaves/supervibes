import Foundation

/// The sleep schedule and clock, as in src/lib/settings-schema.ts.
struct SleepSettings: Hashable, Sendable {
    /// Bedtime, minutes after local midnight.
    var sleepStart: Int
    /// Wake-up time, minutes after local midnight.
    var wakeTime: Int
    /// nil follows the device.
    var clock: Clock?

    static let defaults = SleepSettings(sleepStart: 23 * 60, wakeTime: 7 * 60, clock: nil)

    /// Times are picked in 15-minute steps.
    static let step = 15
    static let times = Array(stride(from: 0, to: 24 * 60, by: step))

    /// Minutes awake per day.
    var awakeMinutes: Int {
        (sleepStart - wakeTime + 24 * 60) % (24 * 60)
    }

    /// Why these can't be saved, or nil if they can.
    var problem: String? {
        sleepStart == wakeTime ? "Bedtime and wake-up time can't be the same." : nil
    }
}

enum Clock: String, CaseIterable, Hashable, Sendable {
    case twelveHour = "12h"
    case twentyFourHour = "24h"

    /// What this Mac uses, for when the person hasn't picked one.
    static var device: Clock {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return pattern.contains("a") ? .twelveHour : .twentyFourHour
    }

    /// "14:30" or "2:30 PM", formatted by hand like the web app's lib/clock.ts.
    func format(minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let hour = m / 60, minute = m % 60
        switch self {
        case .twentyFourHour:
            return String(format: "%02d:%02d", hour, minute)
        case .twelveHour:
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
        }
    }
}

extension SleepSettings {
    /// The clock to show: the person's choice, or the device's until they pick one.
    var effectiveClock: Clock { clock ?? .device }

    static func hoursLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
