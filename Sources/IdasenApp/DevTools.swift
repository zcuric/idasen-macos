import AppKit
import Foundation
import IdasenKit
import SwiftUI

/// Developer helpers, enabled only when the matching command line flags are
/// passed. They allow verifying the UI without bringing windows to the front:
///
///     Idasen --demo --dev-snapshot ~/Desktop/idasen.png
///
/// `--dev-snapshot` renders every app window to PNG after the app has settled,
/// waits for a simulated move to finish when in demo mode, and quits.
@MainActor
enum DevTools {
    static var isSnapshotRun: Bool {
        CommandLine.arguments.contains("--dev-snapshot")
    }

    /// Preview processes never read or overwrite the user's settings or history.
    static let previewDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Idasen-preview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var snapshotPath: String {
        guard let index = CommandLine.arguments.firstIndex(of: "--dev-snapshot"),
              index + 1 < CommandLine.arguments.count
        else {
            return "\(NSHomeDirectory())/Desktop/idasen-snapshot.png"
        }
        return CommandLine.arguments[index + 1]
    }

    /// Schedules a demo move (when in demo mode) followed by a window snapshot.
    static func runSnapshotSequence(model: AppModel) {
        let path = snapshotPath
        MainActor.assumeIsolated {
            model.banner = nil
            if let tab = argumentValue("--dev-tab").flatMap(SidebarItem.init(rawValue:)) {
                model.selection = tab
            } else {
                model.selection = .desk
            }

        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            MainActor.assumeIsolated {
                let size = (argumentValue("--dev-size") ?? "1080x720").split(separator: "x")
                if size.count == 2, let width = Double(size[0]), let height = Double(size[1]),
                   let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.setContentSize(NSSize(width: max(940, width), height: max(640, height)))
                }
                if model.isDemoMode, CommandLine.arguments.contains("--dev-moving") {
                    model.move(toHeightMM: 1100)
                }
            }
        }
        if CommandLine.arguments.contains("--dev-repeat") {
            Task { @MainActor in
                for index in 1...30 {
                    try? await Task.sleep(for: .seconds(2))
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let repeated = url.deletingPathExtension().path + "-\(index)." + url.pathExtension
                    writeSnapshot(path: repeated)
                }
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            writeSnapshot(path: path)
            if CommandLine.arguments.contains("--dev-quit") {
                model.shutdown()
                exit(0)
            }
        }
    }

    /// Writes a synthetic activity history and exits immediately. Run once,
    /// then launch normally:
    ///     Idasen --dev-activity-fixture
    @MainActor
    static func writeActivityFixture() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var days: [DayActivity] = []

        for dayOffset in (0..<21).reversed() {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  let dayEnd = calendar.date(byAdding: .hour, value: 18, to: dayStart),
                  var cursor = calendar.date(byAdding: .hour, value: 8, to: dayStart)
            else { continue }

            var segments: [ActivitySegment] = []
            var transitions = 0
            var standing = dayOffset % 2 == 0
            // Weekends have a short session, weekdays a full day.
            let weekday = calendar.component(.weekday, from: dayStart)
            let cutoff = (weekday == 1 || weekday == 7)
                ? calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayEnd
                : dayEnd

            while cursor < cutoff {
                let duration = Double.random(in: 25...80) * 60
                let end = min(cursor.addingTimeInterval(duration), cutoff)
                segments.append(ActivitySegment(start: cursor, end: end, state: standing ? .standing : .sitting))
                if !segments.isEmpty, segments.count > 1 { transitions += 0 }
                cursor = end
                if end < cutoff { transitions += 1 }
                standing.toggle()
            }

            var samples: [HeightPoint] = []
            if dayOffset == 0 {
                var time = calendar.date(byAdding: .hour, value: 8, to: dayStart) ?? dayStart
                while time < Date() {
                    let wave = sin(time.timeIntervalSince(dayStart) / 5400) * 60
                    samples.append(HeightPoint(time: time, heightMM: 900 + wave))
                    time = time.addingTimeInterval(60)
                }
            }

            days.append(
                DayActivity(
                    day: dayStart,
                    segments: segments,
                    samples: samples,
                    transitions: transitions,
                    minMM: segments.map(\.state).contains(.standing) ? 730 : 730,
                    maxMM: 1100
                )
            )
        }

        JSONStore<[DayActivity]>(filename: "activity.json").save(days)
        FileHandle.standardError.write(Data("dev-activity-fixture: wrote \(days.count) days\n".utf8))
        exit(0)
    }

    static func argumentValue(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              index + 1 < CommandLine.arguments.count
        else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// Fills the activity store with plausible data for UI review.
    @MainActor
    static func seedActivity(_ model: AppModel) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sit = model.sitPreset?.heightMM ?? 730
        let stand = model.standPreset?.heightMM ?? 1100

        for dayOffset in 0..<21 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            guard let dayEnd = calendar.date(byAdding: .hour, value: 18, to: dayStart),
                  let start = calendar.date(byAdding: .hour, value: 8, to: dayStart)
            else { continue }

            var cursor = start
            var isStanding = false
            while cursor < dayEnd {
                let duration = Double.random(in: 35...95) * 60
                let end = min(cursor.addingTimeInterval(duration), dayEnd)
                model.activity.record(
                    heightMM: isStanding ? stand : sit,
                    at: cursor,
                    thresholdMM: (sit + stand) / 2
                )
                model.activity.record(
                    heightMM: isStanding ? stand : sit,
                    at: end,
                    thresholdMM: (sit + stand) / 2
                )
                cursor = end.addingTimeInterval(20)
                isStanding.toggle()
            }
        }
        model.activity.closeOpenSegment()
        model.activity.persist()
    }

    static func writeSnapshot(path: String) {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.frame.height > 200 }
        guard let window = candidates.first(where: { $0.canBecomeMain }) ?? candidates.first,
              let view = window.contentView
        else {
            FileHandle.standardError.write(Data("dev-snapshot: no visible window\n".utf8))
            return
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            try data.write(to: url)
            FileHandle.standardError.write(Data("dev-snapshot: wrote \(url.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("dev-snapshot: \(error)\n".utf8))
        }
    }
}
