// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Onboarding / re-auth: server address plus API token, tested before saving.
struct ConnectView: View {
    @EnvironmentObject var store: AppStore
    @State private var server: String = ""
    @State private var token: String = ""
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "stopwatch")
                Text("Stempeluhr").font(.headline)
            }

            if store.phase == .signInRequired {
                Label("Sign-in required — the token was rejected.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Connect to your Kimai server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Server").font(.caption).foregroundStyle(.secondary)
                TextField("https://kimai.example.com", text: $server)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API token").font(.caption).foregroundStyle(.secondary)
                SecureField("Profile → API in Kimai", text: $token)
                    .textFieldStyle(.roundedBorder)
            }

            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: connect) {
                HStack {
                    if testing { ProgressView().controlSize(.small) }
                    Text(testing ? "Testing…" : "Connect")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(testing || server.trimmed.isEmpty || token.trimmed.isEmpty)

            HStack {
                Spacer()
                Menu {
                    Button("Quit Stempeluhr") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(14)
        .onAppear { if server.isEmpty { server = store.serverURL } }
    }

    private func connect() {
        testing = true
        Task {
            _ = await store.connect(server: server.trimmed, token: token.trimmed)
            testing = false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
