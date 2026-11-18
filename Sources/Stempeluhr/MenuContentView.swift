// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

/// The popover shown when the menu-bar item is clicked.
struct MenuContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch store.phase {
            case .notConfigured, .signInRequired:
                ConnectView()
            case .connected:
                connected
            }
        }
        .frame(width: 300)
        // Refresh every time the popover opens, not only on the manual button.
        .onAppear { Task { await store.refreshOnOpen() } }
    }

    // MARK: - Connected

    @ViewBuilder private var connected: some View {
        header
        totalsStrip
        Divider()
        if store.isRunning {
            runningBody
        } else {
            idleBody
        }
        Divider()
        footer
    }

    // MARK: - Totals

    private var totalsStrip: some View {
        HStack(spacing: 8) {
            statTile("Today", Fmt.hm(store.todayTotal))
            statTile("This week", Fmt.hm(store.weekTotal))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.isRunning, let t = store.tracking.runningTimesheet, let e = store.elapsed {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.hms(e))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    dot(color: Color(hex: t.project.color) ?? .green)
                }
                Text(Fmt.label(t.project))
                    .font(.headline)
                Text(Fmt.label(t.activity) + (t.project.parent.map { " · \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Since \(Fmt.clock(t.begin))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not tracking")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if !store.confirmed, let at = store.lastConfirmedAt {
                Label("Not confirmed · as of \(Fmt.asOf(at))", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    // MARK: - Running

    private var runningBody: some View {
        VStack(spacing: 8) {
            Button(action: { Task { await store.stop() } }) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(store.busy)

            if case .running(_, let others) = store.tracking, others > 0 {
                Text("\(others) more entr\(others == 1 ? "y" : "ies") also running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - Idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.quickStarts.isEmpty {
                quickStartSection
                Divider()
            }
            pickerRow(title: "Project") {
                Picker("Project", selection: Binding(
                    get: { store.selectedProject ?? -1 },
                    set: { store.selectProject($0) }
                )) {
                    if store.selectedProject == nil { Text("Choose…").tag(-1) }
                    ForEach(store.projects) { p in
                        Text(p.customer.map { "\(p.name) · \($0)" } ?? p.name).tag(p.id)
                    }
                }
                .labelsHidden()
            }

            pickerRow(title: "Activity") {
                Picker("Activity", selection: Binding(
                    get: { store.selectedActivity ?? -1 },
                    set: { store.selectedActivity = $0 }
                )) {
                    if store.selectedActivity == nil { Text("Choose…").tag(-1) }
                    ForEach(store.activities) { a in
                        Text(a.name).tag(a.id)
                    }
                }
                .labelsHidden()
                .disabled(store.activities.isEmpty)
            }

            Button(action: { Task { await store.start() } }) {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(store.busy || store.selectedProject == nil || store.selectedActivity == nil)
        }
        .padding(12)
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK START")
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
            ], spacing: 6) {
                ForEach(store.quickStarts) { q in
                    Button { Task { await store.quickStart(q) } } label: {
                        quickStartLabel(q)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.busy)
                }
            }
        }
    }

    private func quickStartLabel(_ q: QuickStart) -> some View {
        let color = Color(hex: q.project.color) ?? .accentColor
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.label(q.project))
                    .font(.caption).fontWeight(.medium)
                    .lineLimit(1)
                Text(Fmt.label(q.activity))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func pickerRow<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            content()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            HStack(spacing: 14) {
                Button(action: { Task { await store.refreshAll() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                if let url = URL(string: store.serverURL), let host = url.host {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .help("Open \(host) in your browser")
                }
                Spacer()
                Menu {
                    Button("Disconnect…") { store.disconnect() }
                    Button("Quit Stempeluhr") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sign out or quit")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
    }

    private func dot(color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12)
    }
}

extension Color {
    /// Parses `#rrggbb`; returns nil on anything else.
    init?(hex: String?) {
        guard var s = hex else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255
        )
    }
}
