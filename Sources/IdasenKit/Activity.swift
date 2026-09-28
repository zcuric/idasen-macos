import Foundation

/// A period of time spent in one sit/stand state.
public struct ActivitySegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var state: SitStandState

    public init(id: UUID = UUID(), start: Date, end: Date, state: SitStandState) {
        self.id = id
        self.start = start
        self.end = end
        self.state = state
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Sparse height sample kept for today's height chart.
public struct HeightPoint: Codable, Equatable, Sendable, Identifiable {
    public var time: Date
    public var heightMM: Double

    public var id: Date { time }

    public init(time: Date, heightMM: Double) {
        self.time = time
        self.heightMM = heightMM
    }
}

/// Aggregated activity for a single calendar day.
public struct DayActivity: Codable, Equatable, Identifiable, Sendable {
    public var day: Date
    public var segments: [ActivitySegment]
    public var samples: [HeightPoint]
    public var transitions: Int
    public var minMM: Double?
    public var maxMM: Double?

    public var id: Date { day }

    public init(
        day: Date,
        segments: [ActivitySegment] = [],
        samples: [HeightPoint] = [],
        transitions: Int = 0,
        minMM: Double? = nil,
        maxMM: Double? = nil
    ) {
        self.day = day
        self.segments = segments
        self.samples = samples
        self.transitions = transitions
        self.minMM = minMM
        self.maxMM = maxMM
    }

    public var standingSeconds: TimeInterval {
        segments.filter { $0.state == .standing }.reduce(0) { $0 + $1.duration }
    }

    public var sittingSeconds: TimeInterval {
        segments.filter { $0.state == .sitting }.reduce(0) { $0 + $1.duration }
    }

    public var trackedSeconds: TimeInterval { standingSeconds + sittingSeconds }

    public var standingRatio: Double {
        let tracked = trackedSeconds
        guard tracked > 0 else { return 0 }
        return standingSeconds / tracked
    }

    public var longestStandingStreak: TimeInterval {
        segments.filter { $0.state == .standing }.map(\.duration).max() ?? 0
    }

    /// The most recent committed state.
    public var currentState: SitStandState? {
        segments.last?.state
    }

    public var isEmpty: Bool { segments.isEmpty && samples.isEmpty }
}

/// Records desk activity over time and persists per-day aggregates.
///
/// Segments are created with a short hysteresis window so brief height blips
/// (a nudge, the desk passing through the threshold) do not create transitions.
@MainActor
public final class ActivityRecorder: ObservableObject {
    public private(set) var today: DayActivity
    public private(set) var history: [DayActivity] = []

    /// Called whenever today's data changes meaningfully (used to refresh UI).
    public var onChange: (() -> Void)?

    private let store: JSONStore<[DayActivity]>
    private let calendar: Calendar
    private let persistenceQueue = DispatchQueue(label: "com.zdravko.idasen.activity", qos: .utility)

    /// A state change must persist this long before it is committed.
    private let hysteresis: TimeInterval = 6
    /// Gaps longer than this are treated as separate sessions.
    private let gapLimit: TimeInterval = 300
    private let sampleInterval: TimeInterval = 60
    private let maximumSamplesPerDay = 2000

    private struct PendingState {
        var state: SitStandState
        var since: Date
    }

    private var pending: PendingState?
    private var lastSampleTime: Date?
    private var lastSampleDate: Date?
    private var lastPublished: Date = .distantPast
    private var lastSaved: Date = .distantPast
    private var retentionDays: Int = 120

    public init(calendar: Calendar = .current, directory: URL? = nil) {
        self.calendar = calendar
        self.store = JSONStore<[DayActivity]>(filename: "activity.json", directory: directory)
        let startOfToday = calendar.startOfDay(for: Date())
        let loaded = store.load(default: [])
        if let persistedToday = loaded.first(where: { calendar.isDate($0.day, inSameDayAs: startOfToday) }) {
            today = persistedToday
        } else {
            today = DayActivity(day: startOfToday)
        }
        history = loaded.filter { !calendar.isDate($0.day, inSameDayAs: startOfToday) }
        lastSampleTime = today.samples.last?.time
        rollOverIfNeeded(now: Date())
    }

    public func configure(retentionDays: Int) {
        self.retentionDays = max(7, retentionDays)
    }

    // MARK: Recording

    /// Feeds a height sample. Call this for every desk notification.
    public func record(heightMM: Double, at date: Date = Date(), thresholdMM: Double) {
        rollOverIfNeeded(now: date)

        let state: SitStandState = heightMM >= thresholdMM ? .standing : .sitting
        lastSampleDate = date

        if let last = today.segments.last, date.timeIntervalSince(last.end) > gapLimit {
            // Desk was not being observed for a while — start a new session.
            pending = nil
            today.segments.append(ActivitySegment(start: date, end: date, state: state))
        } else if let pending {
            if pending.state == state {
                if date.timeIntervalSince(pending.since) >= hysteresis {
                    commit(pending: pending, until: date)
                }
            } else {
                // Returned to the committed state; discard the pending change.
                self.pending = nil
                extendLastSegment(to: date)
            }
        } else if let last = today.segments.last, last.state == state {
            extendLastSegment(to: date)
        } else if today.segments.isEmpty {
            today.segments.append(ActivitySegment(start: date, end: date, state: state))
        } else {
            pending = PendingState(state: state, since: date)
        }

        today.minMM = min(today.minMM ?? heightMM, heightMM)
        today.maxMM = max(today.maxMM ?? heightMM, heightMM)

        let sampleDue = lastSampleTime.map { date.timeIntervalSince($0) >= sampleInterval } ?? true
        if sampleDue {
            lastSampleTime = date
            today.samples.append(HeightPoint(time: date, heightMM: heightMM))
            if today.samples.count > maximumSamplesPerDay {
                today.samples.removeFirst(today.samples.count - maximumSamplesPerDay)
            }
        }

        if date.timeIntervalSince(lastSaved) > 30 {
            persist(synchronously: false)
        }
        publish(at: date)
    }

    private func publish(at date: Date = Date(), force: Bool = false) {
        guard force || date.timeIntervalSince(lastPublished) >= 1 else { return }
        lastPublished = date
        objectWillChange.send()
        onChange?()
    }

    /// Closes the open segment, e.g. when disconnecting or quitting.
    public func closeOpenSegment(at date: Date = Date()) {
        defer { publish(force: true) }
        if let pending {
            commit(pending: pending, until: max(date, pending.since))
        }
        guard today.segments.last != nil else { return }
        extendLastSegment(to: date)
        persist()
    }

    public func reset() {
        defer { publish(force: true) }
        today = DayActivity(day: calendar.startOfDay(for: Date()))
        history = []
        pending = nil
        lastSampleTime = nil
        persistenceQueue.sync { store.delete() }
    }

    public func removeAllHistory() {
        defer { publish(force: true) }
        history = []
        today = DayActivity(day: calendar.startOfDay(for: Date()))
        pending = nil
        lastSampleTime = nil
        lastSampleDate = nil
        persistenceQueue.sync { store.save([]) }
    }

    // MARK: Queries

    /// Days in reverse chronological order including today.
    public func recentDays(_ count: Int) -> [DayActivity] {
        var days: [DayActivity] = [today]
        let sorted = history
            .filter { !calendar.isDate($0.day, inSameDayAs: today.day) }
            .sorted { $0.day > $1.day }
        days.append(contentsOf: sorted.prefix(max(0, count - 1)))
        return days
    }

    public func day(for date: Date) -> DayActivity? {
        if calendar.isDate(date, inSameDayAs: today.day) { return today }
        return history.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// Rolling total of standing minutes over the last `count` days ending today.
    public func standingMinutes(overLastDays count: Int) -> Double {
        recentDays(count).reduce(0) { $0 + $1.standingSeconds } / 60
    }

    public var allDays: [DayActivity] {
        recentDays(3650)
    }

    // MARK: Persistence

    public func persist(synchronously: Bool = true) {
        lastSaved = Date()
        var days = history.filter { !calendar.isDate($0.day, inSameDayAs: today.day) }
        if !today.isEmpty { days.append(today) }
        days.sort { $0.day > $1.day }
        if let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: Date())) {
            days.removeAll { $0.day < cutoff }
        }
        // Samples are only useful for the day in progress; drop them from history
        // so the file stays small.
        for index in days.indices where !calendar.isDate(days[index].day, inSameDayAs: today.day) {
            days[index].samples = []
        }
        history = days.filter { !calendar.isDate($0.day, inSameDayAs: today.day) }
        let snapshot = days
        let store = store
        if synchronously {
            // Flush earlier background writes before quit, reset or explicit saves.
            persistenceQueue.sync { store.save(snapshot) }
        } else {
            persistenceQueue.async { store.save(snapshot) }
        }
    }

    public func exportCSV() -> String {
        var lines = ["date,start,end,state,duration_minutes"]
        let formatter = ISO8601DateFormatter()
        for day in recentDays(3650).reversed() {
            for segment in day.segments {
                lines.append(
                    [
                        ISO8601DateFormatter.day.string(from: segment.start),
                        formatter.string(from: segment.start),
                        formatter.string(from: segment.end),
                        segment.state.rawValue,
                        String(format: "%.2f", segment.duration / 60),
                    ].joined(separator: ",")
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private func commit(pending: PendingState, until date: Date) {
        if let lastIndex = today.segments.indices.last {
            today.segments[lastIndex].end = max(today.segments[lastIndex].start, pending.since)
        }
        today.segments.append(ActivitySegment(start: pending.since, end: date, state: pending.state))
        today.transitions += 1
        self.pending = nil
    }

    private func extendLastSegment(to date: Date) {
        guard let lastIndex = today.segments.indices.last else {
            today.segments.append(ActivitySegment(start: date, end: date, state: .unknown))
            return
        }
        guard date > today.segments[lastIndex].end else { return }
        today.segments[lastIndex].end = date
    }

    private func rollOverIfNeeded(now: Date) {
        let startOfToday = calendar.startOfDay(for: now)
        guard !calendar.isDate(today.day, inSameDayAs: startOfToday) else { return }
        if let lastDate = lastSampleDate {
            closeOpenSegment(at: lastDate)
        }
        if !today.isEmpty {
            history.insert(today, at: 0)
        }
        today = DayActivity(day: startOfToday)
        pending = nil
        lastSampleTime = nil
        persist()
    }
}

extension ISO8601DateFormatter {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
