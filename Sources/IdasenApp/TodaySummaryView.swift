import IdasenKit
import SwiftUI
import UserNotifications

/// Observes the recorder's throttled updates, independently of height telemetry.
struct TodaySummaryView: View {
    @ObservedObject var activity: ActivityRecorder
    @ObservedObject var model: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                StandingReminderButton(model: model)
            }
            ActivityTotalsView(day: activity.today, goalMinutes: model.settings.dailyStandingGoalMinutes, compact: compact)
        }
        .padding(compact ? 12 : 16)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
    }
}

struct ActivityTotalsView: View {
    let day: DayActivity
    let goalMinutes: Double
    var compact = false

    private var goal: Double { max(1, goalMinutes) * 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                metric("Sitting", symbol: "chair.lounge", seconds: day.sittingSeconds)
                metric("Standing", symbol: "figure.stand", seconds: day.standingSeconds)
                if !compact {
                    Spacer(minLength: 0)
                    goalView.frame(maxWidth: 210)
                }
            }
            if compact { goalView }
            Text("Estimated from desk height while connected")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, symbol: String, seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption).foregroundStyle(.secondary)
            Text(Self.duration(seconds))
                .font(.system(size: compact ? 19 : 23, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var goalView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Standing goal")
                Spacer()
                Text("\(Int(min(1, day.standingSeconds / goal) * 100))%")
                    .monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
            ProgressView(value: min(day.standingSeconds, goal), total: goal)
                .accessibilityLabel("Daily standing goal")
                .accessibilityValue("\(Self.duration(day.standingSeconds)) of \(Self.duration(goal))")
        }
    }

    private static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

struct StandingReminderButton: View {
    @ObservedObject var model: AppModel
    @State private var showsPreferences = false

    var body: some View {
        Button {
            showsPreferences = true
        } label: {
            Label(model.settings.remindersEnabled ? "Every \(Int(model.settings.reminderIntervalMinutes)) min" : "Reminders off",
                  systemImage: model.settings.remindersEnabled ? "bell.badge" : "bell")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Configure standing reminders")
        .popover(isPresented: $showsPreferences) {
            VStack(alignment: .leading, spacing: 16) {
                Text("A moment to stand").font(.headline)
                Text("Choose a gentle reminder to change position. Your desk moves only when you ask.")
                    .font(.callout).foregroundStyle(.secondary)
                StandingReminderPreferences(model: model, notifications: model.notifications)
            }
            .padding(20)
            .frame(width: 320)
        }
    }
}

struct StandingReminderPreferences: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NotificationService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Standing reminders", isOn: Binding(
                get: { model.settings.remindersEnabled },
                set: { model.setStandingRemindersEnabled($0) }
            ))
            if model.settings.remindersEnabled {
                Stepper("Every \(Int(model.settings.reminderIntervalMinutes)) minutes",
                        value: model.binding(\.reminderIntervalMinutes), in: 15...120, step: 5)
                Toggle("Only while sitting", isOn: model.binding(\.reminderOnlyWhileSitting))
                Text("Reminders run while your desk is connected. Notifications include a 10-minute snooze.")
                    .font(.caption).foregroundStyle(.secondary)
                if notifications.authorizationStatus == .denied {
                    Label("Allow Idasen in System Settings → Notifications for alerts outside the app.", systemImage: "bell.slash")
                        .font(.caption).foregroundStyle(.secondary)
                } else if notifications.authorizationStatus == .notDetermined {
                    Button("Allow notifications…") { notifications.requestAuthorization() }
                        .buttonStyle(.link)
                }
            }
        }
        .onAppear { if !DevTools.isSnapshotRun { notifications.refreshAuthorization() } }
    }
}

#Preview("Today — compact") {
    ActivityTotalsView(day: DayActivity(day: .now, segments: [
        ActivitySegment(start: .distantPast, end: .distantPast.addingTimeInterval(5400), state: .sitting),
        ActivitySegment(start: .distantPast, end: .distantPast.addingTimeInterval(2100), state: .standing)
    ]), goalMinutes: 120, compact: true)
    .padding().frame(width: 300)
}

#Preview("Today — empty") {
    ActivityTotalsView(day: DayActivity(day: .now), goalMinutes: 120)
        .padding().frame(width: 650)
}
