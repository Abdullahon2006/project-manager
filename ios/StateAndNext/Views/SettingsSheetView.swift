import SwiftUI

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync: SyncService
    
    @State private var serverURL: String = ""
    @State private var testStatusMessage: String? = nil
    @State private var isTesting: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Cloud Server Configuration"), footer: Text("Enter the base URL of your FastAPI backend. Default is the production Heroku deployment.")) {
                    TextField("Server URL", text: $serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting || serverURL.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let msg = testStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("Success") ? .green : .red)
                    }
                }

                Section("Quick URL Presets") {
                    Button("Heroku Production Cloud") {
                        serverURL = "https://project-manager-app-78c6297c8f8b.herokuapp.com"
                    }
                    Button("Local Development (127.0.0.1:8000)") {
                        serverURL = "http://127.0.0.1:8000"
                    }
                }

                Section("Sync Diagnostics") {
                    HStack {
                        Text("Network Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(sync.isOnline ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(sync.isOnline ? "Connected" : "Offline")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Staged Offline Changes")
                        Spacer()
                        Text("\(sync.pendingSyncCount) pending")
                            .foregroundColor(sync.pendingSyncCount > 0 ? .orange : .secondary)
                    }

                    if let lastSync = sync.lastSyncTime {
                        HStack {
                            Text("Last Successful Sync")
                            Spacer()
                            Text(lastSync, format: .dateTime.hour().minute().second())
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { sync.triggerSync() }) {
                        Label("Force Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(sync.pendingSyncCount == 0 && !sync.isOnline)
                }
            }
            .navigationTitle("Connection Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            sync.serverBaseURL = trimmed
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                serverURL = sync.serverBaseURL
            }
        }
    }

    private func testConnection() {
        guard let url = URL(string: "\(serverURL.trimmingCharacters(in: .whitespacesAndNewlines))/api/bento") else {
            testStatusMessage = "Invalid URL format."
            return
        }
        isTesting = true
        testStatusMessage = nil

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    isTesting = false
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        testStatusMessage = "Success! Server is reachable (HTTP \(http.statusCode))."
                    } else {
                        testStatusMessage = "Server returned error status."
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testStatusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
