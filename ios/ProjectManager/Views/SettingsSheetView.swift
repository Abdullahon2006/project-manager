import SwiftUI

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync: SyncService
    @ObservedObject var theme = ThemeManager.shared

    @State private var serverURL: String = ""
    @State private var testStatusMessage: String? = nil
    @State private var isTesting: Bool = false
    @State private var customUrlText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Appearance & Theme
                Section("Appearance & Theme") {
                    Picker("Color Mode", selection: $theme.appearanceMode) {
                        Text("System").tag("system")
                        Text("Light (Daylight)").tag("light")
                        Text("Dark (Obsidian)").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // Section 2: Wallpaper Gallery
                Section("Atmospheric Wallpapers") {
                    // Option None
                    Button {
                        theme.selectedWallpaperId = "none"
                    } label: {
                        HStack {
                            Text("⬜ Clean Canvas (No Wallpaper)")
                                .foregroundColor(.primary)
                            Spacer()
                            if theme.selectedWallpaperId == "none" {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // Presets
                    ForEach(ThemeManager.presets) { preset in
                        Button {
                            theme.selectedWallpaperId = preset.id
                        } label: {
                            HStack {
                                Text("\(preset.thumbnail) \(preset.name)")
                                    .foregroundColor(.primary)
                                Spacer()
                                if theme.selectedWallpaperId == preset.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }

                    // Custom URL
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            theme.selectedWallpaperId = "custom"
                        } label: {
                            HStack {
                                Text("🔗 Custom Image URL")
                                    .foregroundColor(.primary)
                                Spacer()
                                if theme.selectedWallpaperId == "custom" {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }

                        if theme.selectedWallpaperId == "custom" {
                            TextField("https://images.unsplash.com/...", text: $customUrlText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .onSubmit {
                                    theme.customWallpaperUrl = customUrlText
                                }
                        }
                    }

                    if theme.selectedWallpaperId != "none" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wallpaper Dimming: \(Int(theme.wallpaperDimming * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Slider(value: $theme.wallpaperDimming, in: 0.05...0.70, step: 0.05)
                        }
                    }
                }

                // Section 3: Cloud Server Configuration
                Section(header: Text("Cloud Server Configuration"), footer: Text("Enter the base URL of your FastAPI backend. Production is hosted on Heroku.")) {
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
            .navigationTitle("Settings & Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            sync.serverBaseURL = trimmed
                        }
                        if theme.selectedWallpaperId == "custom" {
                            theme.customWallpaperUrl = customUrlText
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                serverURL = sync.serverBaseURL
                customUrlText = theme.customWallpaperUrl
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
