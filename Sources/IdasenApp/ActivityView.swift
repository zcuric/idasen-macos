import Charts
import IdasenKit
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var activity: ActivityRecorder

    private var accent: Color { Theme.accent(model.settings.accent) }
    private var today: DayActivity { activity.today }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statsGrid(compact: geometry.size.width < 900)
                    if geometry.size.width < 760 {
                        VStack(spacing: 16) {
                            weeklyChart
                            todayTimeline
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            weeklyChart
                            todayTimeline
                                .frame(width: min(320, geometry.size.width * 0.34))
                        }
                    }
                    heightChart
                    historyList
                }
                .padding(24)
                .frame(maxWidth: 1220)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Activity")
                    .font(.system(size: 26, weight: .semibold))
                Text("Idasen tracks how long you sit and stand while connected.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
            .disabled(activity.allDays.isEmpty)
        }
    }

    // MARK: Stats

    private func statsGrid(compact: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: 12) {
            goalCard
            statCard(
                title: "Sitting today",
                value: formatDuration(today.sittingSeconds),
                symbol: "chair.lounge.fill",
                color: .orange
            )
            statCard(
                title: "Transitions",
                value: "\(today.transitions)",
                symbol: "arrow.up.arrow.down",
                color: .purple
            )
            statCard(
                title: "Longest stand",
                value: formatDuration(today.longestStandingStreak),
                symbol: "figure.stand",
                color: .blue
            )
        }
    }

    private var goalCard: some View {
        let goalMinutes = max(1, model.settings.dailyStandingGoalMinutes)
        let minutes = today.standingSeconds / 60
        let fraction = min(1, minutes / goalMinutes)

        return ContentCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(.primary.opacity(0.09), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            Theme.gradient(fraction >= 1 ? .green : accent),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
                    VStack(spacing: 0) {
                        Text("\(Int(fraction * 100))%")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Standing today")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(formatDuration(today.standingSeconds))
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Goal \(Int(goalMinutes)) min")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .frame(minHeight: 64)
        }
    }

    private func statCard(title: String, value: String, symbol: String, color: Color) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
    }

    // MARK: Charts

    private struct DayPoint: Identifiable {
        let day: Date
        let minutes: Double

        var id: Date { day }
    }

    private var weekPoints: [DayPoint] {
        activity.recentDays(14).reversed().map {
            DayPoint(day: $0.day, minutes: $0.standingSeconds / 60)
        }
    }

    private var weeklyChart: some View {
        let points = weekPoints
        return ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Standing time", subtitle: "Last 14 days", symbol: "chart.bar.fill")

                if points.allSatisfy({ $0.minutes < 0.1 }) {
                    EmptyStateView(
                        symbol: "chart.bar",
                        title: "Nothing tracked yet",
                        message: "Standing time appears here once your desk is connected."
                    )
                } else {
                    Chart {
                        ForEach(points) { point in
                            BarMark(
                                x: .value("Day", point.day, unit: .day),
                                y: .value("Minutes", point.minutes)
                            )
                            .foregroundStyle(Theme.gradient(accent))
                            .cornerRadius(5)
                        }
                        RuleMark(y: .value("Daily goal", model.settings.dailyStandingGoalMinutes))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text("\(Int(minutes))m")
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 180)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todayTimeline: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Today", subtitle: "Sit / stand timeline", symbol: "clock.fill")

                if today.segments.isEmpty {
                    EmptyStateView(
                        symbol: "clock",
                        title: "No activity yet",
                        message: "Connect the desk and your day will be charted here."
                    )
                } else {
                    GeometryReader { geometry in
                        let start = today.segments.first?.start ?? Date()
                        let end = today.segments.last?.end ?? Date()
                        let span = max(end.timeIntervalSince(start), 60)

                        ZStack(alignment: .topLeading) {
                            Capsule().fill(.primary.opacity(0.07))

                            ForEach(today.segments) { segment in
                                let offset = segment.start.timeIntervalSince(start) / span
                                let width = max(segment.duration / span, 0.004)
                                Capsule()
                                    .fill(segment.state == .standing ? AnyShapeStyle(Theme.gradient(accent)) : AnyShapeStyle(Color.orange.opacity(0.75)))
                                    .frame(width: geometry.size.width * width)
                                    .offset(x: geometry.size.width * offset)
                            }
                        }
                        .frame(height: 14)
                    }
                    .frame(height: 14)

                    HStack {
                        legend(color: accent, text: "Standing \(formatDuration(today.standingSeconds))")
                        legend(color: .orange, text: "Sitting \(formatDuration(today.sittingSeconds))")
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 6) {
                        detailRow("Standing ratio", "\(Int((today.standingRatio * 100).rounded()))%")
                        detailRow("Desk range", rangeText)
                        detailRow("Last 7 days standing", formatDuration(activity.recentDays(7).reduce(0) { $0 + $1.standingSeconds }))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rangeText: String {
        guard let min = today.minMM, let max = today.maxMM else { return "—" }
        return "\(model.unit.format(millimeters: min)) – \(model.unit.format(millimeters: max))"
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var heightChart: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Height today (\(model.unit.shortTitle))", subtitle: nil, symbol: "ruler.fill")

                if today.samples.count < 2 {
                    EmptyStateView(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Not enough data yet",
                        message: "A height chart builds up as you use the desk."
                    )
                } else {
                    Chart(today.samples) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Height", model.unit.value(fromMillimeters: point.heightMM))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.gradient(accent))
                        AreaMark(
                            x: .value("Time", point.time),
                            y: .value("Height", model.unit.value(fromMillimeters: point.heightMM))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.25), accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .chartYScale(domain: model.unit.value(fromMillimeters: model.settings.heightScale.minimumMM)...model.unit.value(fromMillimeters: model.settings.heightScale.maximumMM))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                            AxisValueLabel {
                                if let height = value.as(Double.self) {
                                    Text("\(Int(height))")
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
    }

    private var historyList: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "History", subtitle: "Last 30 days", symbol: "calendar")

                let days = activity.recentDays(30).filter { !$0.isEmpty }
                if days.isEmpty {
                    EmptyStateView(
                        symbol: "calendar",
                        title: "No history yet",
                        message: "Your daily sit/stand totals will be listed here."
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            HistoryRow(day: day, unit: model.unit, accent: accent)
                            if index < days.count - 1 {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) m"
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "idasen-activity.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? activity.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct HistoryRow: View {
    var day: DayActivity
    var unit: LengthUnit
    var accent: Color

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.day)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isToday ? "Today" : day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: 12.5, weight: isToday ? .semibold : .regular))
                Text("\(day.transitions) transitions")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 150, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.orange.opacity(0.35))
                    Capsule()
                        .fill(Theme.gradient(accent))
                        .frame(width: max(2, geometry.size.width * day.standingRatio))
                }
            }
            .frame(height: 8)

            Text("\(Int((day.standingRatio * 100).rounded()))%")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)

            Text(standingText)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private var standingText: String {
        let minutes = Int((day.standingSeconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) m" : "\(minutes) min"
    }
}
