import Foundation

/// A clock-injected schedule independent of Bluetooth and notification permission.
/// Starts a fresh interval on opt-in, reconnect, or a new sitting session.
public struct StandingReminderSchedule: Sendable {
    private var anchor: Date?
    private var session: Date?
    private var snoozedUntil: Date?

    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func snooze(at now: Date) {
        snoozedUntil = now.addingTimeInterval(10 * 60)
    }

    public mutating func isDue(
        at now: Date, enabled: Bool, connected: Bool, moving: Bool,
        sittingSince: Date?, onlyWhileSitting: Bool, intervalMinutes: Double
    ) -> Bool {
        guard enabled, connected, !onlyWhileSitting || sittingSince != nil else {
            reset()
            return false
        }
        if anchor == nil || (onlyWhileSitting && session != sittingSince) {
            anchor = now
            session = sittingSince
        }
        guard !moving else { return false }
        let deadline = snoozedUntil ?? anchor!.addingTimeInterval(max(5, intervalMinutes) * 60)
        guard now >= deadline else { return false }
        anchor = now
        snoozedUntil = nil
        return true
    }
}
