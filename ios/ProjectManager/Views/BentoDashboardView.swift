import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BentoDashboardView: View {
    @StateObject private var sync = SyncService.shared
    @StateObject private var theme = ThemeManager.shared

    @State private var folders: [FolderBento] = []
    @State private var isLoading: Bool = true
    @State private var searchQuery: String = ""
    @State private var activeTab: DashboardTab = .active
    @State private var fieldFilter: FieldFilter = .all

    @State private var showingNewProjectSheet = false
    @State private var showingNewFieldSheet = false
    @State private var folderToEdit: FolderBento? = nil
    @State private var folderToDelete: FolderBento? = nil
    @State private var showingSettingsSheet = false

    enum DashboardTab: String, CaseIterable, Identifiable {
        case active = "Active Fields"
        case archive = "Finished Archive"
        var id: String { rawValue }
    }

    enum FieldFilter: String, CaseIterable, Identifiable {
        case all = "All Fields"
        case needsAction = "Needs Next Action"
        var id: String { rawValue }
    }

    // Computed Stats
    var totalProjectsCount: Int {
        folders.reduce(0) { $0 + $1.projectCount }
    }

    var totalNextActionsCount: Int {
        folders.reduce(0) { sum, folder in
            sum + folder.recentProjects.filter { $0.nextAction != nil && !$0.nextAction!.isEmpty }.count
        }
    }

    // Projects with no next actions set
    var projectsNeedingActions: [ProjectSummary] {
        folders.flatMap { $0.recentProjects }.filter {
            $0.nextAction == nil || $0.nextAction!.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // Search Results across all folders
    var searchResults: [ProjectSummary] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let q = searchQuery.lowercased()
        return folders.flatMap { $0.recentProjects }.filter {
            $0.title.lowercased().contains(q) || ($0.nextAction?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    
                    // Top Segmented Mode Switcher
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

                // Global Floating Action Buttons (Active Tab Only)
                if activeTab == .active && searchQuery.isEmpty {
                    HStack(spacing: 12) {
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            showingNewFieldSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                Text("New Field")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                        }

                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            showingNewProjectSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("New Project")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: Color.blue.opacity(0.35), radius: 10, y: 5)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
            .withAppWallpaper()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Text("Project Manager")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        // Sync status pill
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
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }

                        // Settings / Wallpaper button
                        Button(action: { showingSettingsSheet = true }) {
                            Image(systemName: "paintpalette.fill")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search projects or next actions...")
            .sheet(isPresented: $showingNewProjectSheet) {
                QuickNewProjectView(onCreated: {
                    Task { await loadBento() }
                })
            }
            .sheet(isPresented: $showingNewFieldSheet) {
                FieldEditModalView(onSaved: { _ in
                    Task { await loadBento() }
                })
            }
            .sheet(item: $folderToEdit) { folder in
                FieldEditModalView(
                    folderToEdit: folder,
                    onSaved: { _ in
                        Task { await loadBento() }
                    },
                    onDeleted: {
                        withAnimation {
                            folders.removeAll { $0.id == folder.id }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsSheetView(sync: sync)
            }
            .confirmationDialog(
                "Delete Field?",
                isPresented: Binding(
                    get: { folderToDelete != nil },
                    set: { if !$0 { folderToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Field & Projects", role: .destructive) {
                    if let f = folderToDelete {
                        deleteField(f)
                    }
                    folderToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    folderToDelete = nil
                }
            } message: {
                Text("Deleting '\(folderToDelete?.name ?? "this field")' will permanently remove all projects inside it. This cannot be undone.")
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
        if sync.isSyncing { return "Syncing" }
        if !sync.isOnline { return "Offline" }
        if sync.pendingSyncCount > 0 { return "Staged (\(sync.pendingSyncCount))" }
        return "Synced"
    }

    private var activeBentoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                
                // If Search Active, show search results
                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResultsSection
                } else {
                    // Quick Stats Row
                    quickMetricsRow
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Quick Filter Chips
                    HStack(spacing: 8) {
                        DashboardFilterChip(
                            title: "All Fields (\(folders.count))",
                            isSelected: fieldFilter == .all
                        ) {
                            fieldFilter = .all
                        }

                        DashboardFilterChip(
                            title: "Needs Action (\(projectsNeedingActions.count))",
                            isSelected: fieldFilter == .needsAction
                        ) {
                            fieldFilter = .needsAction
                        }
                    }
                    .padding(.horizontal)

                    if fieldFilter == .needsAction {
                        needsActionProjectsSection
                    } else {
                        // Bento Grid
                        if isLoading && folders.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading Workspaces...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else if folders.isEmpty {
                            emptyStateView
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                                ForEach(folders) { folder in
                                    NavigationLink(destination: FolderProjectsListView(folder: folder)) {
                                        BentoFolderCard(
                                            folder: folder,
                                            onEdit: {
                                                folderToEdit = folder
                                            },
                                            onDelete: {
                                                folderToDelete = folder
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            folderToEdit = folder
                                        } label: {
                                            Label("Edit Field", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            folderToDelete = folder
                                        } label: {
                                            Label("Delete Field", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom, 90)
        }
    }

    // MARK: - Quick Metrics Row
    private var quickMetricsRow: some View {
        HStack(spacing: 10) {
            MetricPill(icon: "⚡", label: "Fields", value: "\(folders.count)")
            MetricPill(icon: "📂", label: "Projects", value: "\(totalProjectsCount)")
            MetricPill(icon: "🎯", label: "Next Actions", value: "\(totalNextActionsCount)")
        }
    }

    // MARK: - Needs Action Projects View
    private var needsActionProjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects Needing Next Actions")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if projectsNeedingActions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("All projects have defined next actions!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(projectsNeedingActions) { proj in
                        NavigationLink(destination: ProjectDetailView(projectId: proj.id, initialTitle: proj.title)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(proj.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("⚠️ No active next action")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Search Results Section
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Results (\(searchResults.count))")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if searchResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No projects matching '\(searchQuery)'")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(searchResults) { proj in
                        NavigationLink(destination: ProjectDetailView(projectId: proj.id, initialTitle: proj.title)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(proj.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if let next = proj.nextAction {
                                        Text("➔ \(next)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No Fields Found")
                .font(.headline)
            Text("Tap '+ New Field' below to organize your projects.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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

    private func deleteField(_ folder: FolderBento) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation {
            folders.removeAll { $0.id == folder.id }
        }
        Task {
            try? await sync.deleteFolder(id: folder.id)
        }
    }
}

// MARK: - Dashboard Filter Chip
struct DashboardFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.primary.opacity(0.06))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric Pill
struct MetricPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.headline)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Bento Card Component
struct BentoFolderCard: View {
    let folder: FolderBento
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Folder header
            HStack(spacing: 6) {
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

                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let edit = onEdit {
                            Button(action: edit) {
                                Label("Edit Field", systemImage: "pencil")
                            }
                        }
                        if let del = onDelete {
                            Button(role: .destructive, action: del) {
                                Label("Delete Field", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
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
                                    .foregroundColor(.blue)
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
