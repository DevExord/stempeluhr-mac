// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Entry point. Normally launches the SwiftUI menu-bar app. With
/// `selftest <baseURL> <token>` it runs a headless check of the Kimai client
/// (connect, list, start, stop) and exits — used for CI / manual verification
/// against `build-aux/mock-kimai.py`.
@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "selftest" {
            runSelfTest(args: args)
            return
        }
        StempeluhrApp.main()
    }

    private static func runSelfTest(args: [String]) {
        guard args.count >= 4 else {
            FileHandle.standardError.write(Data("usage: Stempeluhr selftest <baseURL> <token>\n".utf8))
            exit(2)
        }
        let base = args[2], token = args[3]
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        Task {
            ok = await SelfTest.run(base: base, token: token)
            sem.signal()
        }
        sem.wait()
        exit(ok ? 0 : 1)
    }
}

enum SelfTest {
    static func run(base: String, token: String) async -> Bool {
        let client = KimaiClient(baseURL: base, token: token)
        func log(_ s: String) { print("• \(s)") }
        do {
            let (v, u) = try await client.testConnection()
            log("connected: Kimai \(v.version), user \(u.username ?? "?"), tz \(u.timezone ?? "?")")

            let projects = try await client.projects()
            log("projects: \(projects.count) — \(projects.map(\.name).prefix(3).joined(separator: ", "))")
            guard let p = projects.first else { print("✗ no projects"); return false }

            let activities = try await client.activities(project: p.id)
            log("activities for \(p.name): \(activities.map(\.name).joined(separator: ", "))")
            guard let a = activities.first else { print("✗ no activities"); return false }

            let before = try await client.active()
            log("active before: \(before.value.count) running, clock offset \(before.serverDate.map { String(format: "%.0fs", KimaiTime.clockOffset(serverDate: $0, received: before.received)) } ?? "n/a")")

            let now = Date().addingTimeInterval(before.serverDate.map { KimaiTime.clockOffset(serverDate: $0, received: before.received) } ?? 0)
            let started = try await client.start(StartRequest(project: p.id, activity: a.id, description: "selftest"), now: now)
            log("started entry #\(started.value.id) at \(Fmt.clock(started.value.begin))")

            let during = try await client.active()
            guard Tracking.fromActive(during.value).runningTimesheet?.id == started.value.id else {
                print("✗ started entry not reported as active"); return false
            }
            log("active during: running #\(started.value.id) ✓")

            let stopped = try await client.stop(id: started.value.id)
            log("stopped entry #\(stopped.value.id), end \(stopped.value.end.map(Fmt.clock) ?? "nil")")

            let after = try await client.active()
            guard Tracking.fromActive(after.value).runningTimesheet == nil else {
                print("✗ still running after stop"); return false
            }
            log("active after: idle ✓")

            // Overview: recent combos (with colours) + today/week totals.
            var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
            let since = cal.date(byAdding: .day, value: -14, to: Date())!
            let entries = try await client.history(since: since)
            guard !entries.isEmpty else { print("✗ no finished history"); return false }

            var seen = Set<String>(); var quick: [QuickStart] = []
            for t in entries {
                let q = QuickStart(project: t.project, activity: t.activity)
                if seen.insert(q.id).inserted { quick.append(q); if quick.count == 4 { break } }
            }
            log("quick-start combos: \(quick.count)")
            for q in quick {
                log("  • \(Fmt.label(q.project)) · \(Fmt.label(q.activity))  colour \(q.project.color ?? "none")")
            }
            guard quick.contains(where: { $0.project.color != nil }) else {
                print("✗ no colours came back on history entries"); return false
            }

            func dur(_ t: Timesheet) -> TimeInterval { t.end.map { max(0, $0.timeIntervalSince(t.begin)) } ?? 0 }
            let startDay = cal.startOfDay(for: Date())
            let weekComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            let startWeek = cal.date(from: weekComps)!
            let today = entries.filter { $0.begin >= startDay }.reduce(0) { $0 + dur($1) }
            let week = entries.filter { $0.begin >= startWeek }.reduce(0) { $0 + dur($1) }
            log("today total: \(Fmt.hm(today))   week total: \(Fmt.hm(week))")
            guard week >= today else { print("✗ week total < today total"); return false }

            print("✓ self-test passed")
            return true
        } catch {
            print("✗ \((error as? KimaiError)?.errorDescription ?? error.localizedDescription)")
            return false
        }
    }
}
