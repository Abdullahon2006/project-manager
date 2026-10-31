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

    @State private var showingActionSheet = false
    @State private var showingNewProjectSheet = false
    @State private var showingNewFieldSheet = false
    @State private var folderToEdit: FolderBento? = nil
    @State private var folderToDelete: FolderBento? = nil
    @State private var showingSettingsSheet = false

    enum DashboardTab: String, CaseIterable, Identifiable {
        case active = "Workspaces"
        case archive = "Archive"
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
                    
                    // Top Custom Glass Mode Switcher
                    customDashboardTabPicker
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    if activeTab == .active {
                        activeBentoView
                    } else {
                        FinishedArchiveView(sync: sync)
                    }
                }

                // Global Floating Action Button (Active Tab Only)
                if activeTab == .active && searchQuery.isEmpty {
                    floatingNewButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                }
            }
            .withAppWallpaper()
            .navigationTitle("Project Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Text("Project Manager")
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        // Sync status pill
                        Button(action: { showingSettingsSheet = true }) {
                            HStack(spacing: 5) {
                                ZStack {
                                    if sync.isSyncing {
                                        ProgressView()
                                            .scaleEffect(0.55)
                                    } else {
                                        Circle()
                                            .fill(statusColor)
                                            .frame(width: 7, height: 7)
                                    }
                                }
                                .frame(width: 9, height: 9)

                                Text(statusText)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.systemBackground).opacity(0.65))
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }

                        // Settings / Wallpaper button
                        Button(action: { showingSettingsSheet = true }) {
                            Image(systemName: "paintpalette.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color(.systemBackground).opacity(0.65))
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search projects or next actions...")
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
                "Create New",
                isPresented: $showingActionSheet,
                titleVisibility: .visible
            ) {
                Button("New Project") {
                    showingNewProjectSheet = true
                }
                Button("New Field") {
                    showingNewFieldSheet = true
                }
                Button("Cancel", role: .cancel) { }
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
        if !sync.isOnline { return "Offline" }
        if sync.isSyncing { return "Syncing" }
        if sync.pendingSyncCount > 0 { return "Staged (\(sync.pendingSyncCount))" }
        return "Synced"
    }

    private var statusColor: Color {
        if !sync.isOnline { return .gray }
        if sync.pendingSyncCount > 0 { return .orange }
        return .green
    }

    // MARK: - Custom Glass Dashboard Mode Picker
    private var customDashboardTabPicker: some View {
        HStack(spacing: 0) {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeTab = .active
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.caption2)
                    Text("Workspaces (\(folders.count))")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(activeTab == .active ? Color(.systemBackground).opacity(0.85) : Color.clear)
                .foregroundColor(activeTab == .active ? .primary : .secondary)
                .clipShape(Capsule())
                .shadow(color: activeTab == .active ? Color.black.opacity(0.08) : Color.clear, radius: 4, y: 1)
            }
            .buttonStyle(.plain)

            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeTab = .archive
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox.fill")
                        .font(.caption2)
                    Text("Archive")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(activeTab == .archive ? Color(.systemBackground).opacity(0.85) : Color.clear)
                .foregroundColor(activeTab == .archive ? .primary : .secondary)
                .clipShape(Capsule())
                .shadow(color: activeTab == .archive ? Color.black.opacity(0.08) : Color.clear, radius: 4, y: 1)
            }
            .buttonStyle(.plain)
        }
        .padding(3)
        .background(Color(.systemBackground).opacity(0.45))
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Active Bento View
    private var activeBentoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                
                // If Search Active, show search results
                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResultsSection
                } else {
                    // Unified Metrics Banner
                    quickMetricsRow
                        .padding(.horizontal, 16)

                    // Quick Filter Chips (Safe on all device widths)
                    ScrollView(.horizontal, showsIndicators: false) {
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
                        .padding(.horizontal, 16)
                    }

                    if fieldFilter == .needsAction {
                        needsActionProjectsSection
                    } else {
                        // Bento Stream Cards
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
                            LazyVStack(spacing: 14) {
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
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 96)
        }
    }

    // MARK: - Unified Metrics Banner (No Overflow)
    private var quickMetricsRow: some View {
        HStack(spacing: 0) {
            metricItem(icon: "⚡", value: "\(folders.count)", label: "Fields")
            Spacer()
            Divider().frame(height: 18).opacity(0.3)
            Spacer()
            metricItem(icon: "📂", value: "\(totalProjectsCount)", label: "Projects")
            Spacer()
            Divider().frame(height: 18).opacity(0.3)
            Spacer()
            metricItem(icon: "🎯", value: "\(totalNextActionsCount)", label: "Actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.72))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func metricItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(icon)
                .font(.subheadline)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    // MARK: - Floating New Button
    private var floatingNewButton: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showingActionSheet = true
        }) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                Text("New")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.blue)
            .clipShape(Capsule())
            .shadow(color: Color.blue.opacity(0.4), radius: 10, y: 5)
        }
    }

    // MARK: - Needs Action Projects View
    private var needsActionProjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects Needing Next Actions")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

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
                            .background(Color(.systemBackground).opacity(0.72))
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
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
                .padding(.horizontal, 16)

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
                            .background(Color(.systemBackground).opacity(0.72))
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
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
            Text("Tap '+ New' below to create your first field workspace.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: { showingNewFieldSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                    Text("Create New Field")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
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
                .background(isSelected ? Color.blue : Color(.systemBackground).opacity(0.6))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Stream Card Component (Full Width, Zero Clipping)
struct BentoFolderCard: View {
    let folder: FolderBento
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Folder header: Icon Badge + Title + Count Badge + Menu
            HStack(spacing: 10) {
                Text(folder.displayIcon)
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: folder.color).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Text("\(folder.projectCount) \(folder.projectCount == 1 ? "project" : "projects")")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Spacer()

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
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(.tertiarySystemBackground).opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Previews of recent projects
            if folder.recentProjects.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("No active projects — tap to open field")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                VStack(spacing: 7) {
                    ForEach(folder.recentProjects.prefix(3)) { proj in
                        HStack(alignment: .center, spacing: 8) {
                            Circle()
                                .fill(Color(hex: folder.color))
                                .frame(width: 6, height: 6)

                            Text(proj.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                                .layoutPriority(1)

                            Spacer(minLength: 6)

                            if let next = proj.nextAction, !next.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(next)
                                        .font(.caption2.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                                .frame(maxWidth: 160, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground).opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.74))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
