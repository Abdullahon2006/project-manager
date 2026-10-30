import SwiftUI

struct BentoDashboardView: View {
    @StateObject private var sync = SyncService.shared

    @State private var folders: [FolderBento] = []
    @State private var isLoading: Bool = true
    @State private var showingNewProjectSheet = false
    @State private var showingSettingsSheet = false
    @State private var activeTab: DashboardTab = .active

    enum DashboardTab: String, CaseIterable, Identifiable {
        case active = "Active Bento"
        case archive = "Finished Archive"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    
                    // Segmented Control Switcher
                    Picker("Dashboard Mode", selection: $activeTab) {
                        ForEach(DashboardTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    if activeTab == .active {
                        activeBentoView
                    } else {
                        FinishedArchiveView(sync: sync)
                    }
                }

                // Global Floating Add Button (only on active tab)
                if activeTab == .active {
                    Button(action: { showingNewProjectSheet = true }) {
                        Image(systemName: "plus")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 58, height: 58)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: Color.blue.opacity(0.35), radius: 10, y: 5)
                    }
                    .padding(.trailing, 22)
                    .padding(.bottom, 22)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("State & Next")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettingsSheet = true }) {
                        HStack(spacing: 6) {
                            if sync.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Circle()
                                    .fill(sync.isOnline ? (sync.pendingSyncCount > 0 ? Color.orange : Color.green) : Color.gray)
                                    .frame(width: 8, height: 8)
                            }

                            Text(statusText)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)

                            Image(systemName: "gearshape")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                QuickNewProjectView {
                    Task { await loadBento() }
                }
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsSheetView(sync: sync)
            }
            .alert("Sync Conflict Detected", isPresented: Binding(
                get: { sync.syncConflictAlert != nil },
                set: { if !$0 { sync.syncConflictAlert = nil } }
            )) {
                Button("Dismiss", role: .cancel) { }
            } message: {
                Text(sync.syncConflictAlert ?? "")
            }
            .refreshable {
                await loadBento()
            }
            .task {
                await loadBento()
            }
        }
    }

    private var statusText: String {
        if sync.isSyncing {
            return "Syncing"
        }
        if !sync.isOnline {
            return "Offline"
        }
        if sync.pendingSyncCount > 0 {
            return "Staged (\(sync.pendingSyncCount))"
        }
        return "Synced"
    }

    private var activeBentoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                // Section Title
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Overview")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Fields of Focus & Immediate Next Actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if isLoading && folders.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading Bento Folders...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if folders.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No Fields Found")
                            .font(.headline)
                        Text("Pull down to refresh or check server connection in settings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // Bento 2-Column Grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(folders) { folder in
                            NavigationLink(destination: FolderProjectsListView(folder: folder)) {
                                BentoFolderCard(folder: folder)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 90)
        }
    }

    private func loadBento() async {
        do {
            let fetched = try await sync.fetchBento()
            await MainActor.run {
                self.folders = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Bento Card Component

struct BentoFolderCard: View {
    let folder: FolderBento

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Folder header
            HStack {
                Text(folder.icon)
                    .font(.title2)
                Spacer()
                Text("\(folder.projectCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }

            Text(folder.name)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .foregroundColor(.primary)

            Divider()

            // Previews of recent projects
            if folder.recentProjects.isEmpty {
                VStack {
                    Spacer(minLength: 4)
                    Text("No active projects")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer(minLength: 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(folder.recentProjects.prefix(2)) { proj in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proj.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .foregroundColor(.primary)

                            if let next = proj.nextAction, !next.isEmpty {
                                Text("➔ \(next)")
                                    .font(.caption2)
                                    .foregroundColor(.blue.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 160)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
