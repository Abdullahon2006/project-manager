import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FolderProjectsListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync = SyncService.shared

    @State private var folder: FolderBento
    @State private var projects: [ProjectSummary] = []
    @State private var isLoading: Bool = true
    @State private var selectedStatus: ProjectFilter = .active
    @State private var selectedSort: SortOrder = .recent
    @State private var searchQuery: String = ""
    @State private var showingAddProjectSheet: Bool = false
    @State private var showingEditFolderSheet: Bool = false
    @State private var showDeleteFolderConfirmation: Bool = false
    @State private var errorMessage: String? = nil

    init(folder: FolderBento) {
        _folder = State(initialValue: folder)
    }

    enum ProjectFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case completed = "Completed"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case alphabetical = "Name (A-Z)"
        case nextAction = "Has Action"
        var id: String { rawValue }
    }

    var activeCount: Int {
        projects.filter { $0.status == "active" }.count
    }

    var completedCount: Int {
        projects.filter { $0.status == "completed" }.count
    }

    var filteredProjects: [ProjectSummary] {
        var list = projects
        if selectedStatus == .active {
            list = list.filter { $0.status == "active" }
        } else {
            list = list.filter { $0.status == "completed" }
        }

        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                ($0.nextAction?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }

        switch selectedSort {
        case .recent:
            return list.sorted { ($0.updatedAt ?? Date.distantPast) > ($1.updatedAt ?? Date.distantPast) }
        case .alphabetical:
            return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .nextAction:
            return list.sorted {
                let hasA = ($0.nextAction != nil && !$0.nextAction!.isEmpty) ? 1 : 0
                let hasB = ($1.nextAction != nil && !$1.nextAction!.isEmpty) ? 1 : 0
                return hasA > hasB
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Custom Glass Filter & Sort Control Bar
            HStack(spacing: 10) {
                // Custom Glass Mode Switcher
                HStack(spacing: 0) {
                    Button(action: {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedStatus = .active
                        }
                    }) {
                        Text("Active (\(activeCount))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selectedStatus == .active ? Color(.systemBackground).opacity(0.85) : Color.clear)
                            .foregroundColor(selectedStatus == .active ? .primary : .secondary)
                            .clipShape(Capsule())
                            .shadow(color: selectedStatus == .active ? Color.black.opacity(0.08) : Color.clear, radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedStatus = .completed
                        }
                    }) {
                        Text("Completed (\(completedCount))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selectedStatus == .completed ? Color(.systemBackground).opacity(0.85) : Color.clear)
                            .foregroundColor(selectedStatus == .completed ? .primary : .secondary)
                            .clipShape(Capsule())
                            .shadow(color: selectedStatus == .completed ? Color.black.opacity(0.08) : Color.clear, radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(Color(.systemBackground).opacity(0.45))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))

                // Sort Menu
                Menu {
                    Picker("Sort By", selection: $selectedSort) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(9)
                        .background(Color(.systemBackground).opacity(0.65))
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if isLoading && projects.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading projects in \(folder.name)...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredProjects.isEmpty {
                VStack(spacing: 14) {
                    Text(folder.displayIcon)
                        .font(.system(size: 48))
                        .frame(width: 72, height: 72)
                        .background(Color(hex: folder.color).opacity(0.18))
                        .clipShape(Circle())

                    Text(selectedStatus == .active ? "No Active Projects" : "No Completed Projects")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(selectedStatus == .active ? "Create your first project in this field to track next actions." : "Finished projects will appear here once archived.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    if selectedStatus == .active {
                        Button(action: { showingAddProjectSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("New Project")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredProjects) { project in
                            NavigationLink(destination: ProjectDetailView(projectId: project.id, initialTitle: project.title)) {
                                ProjectRowCard(project: project, folderColor: folder.color)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    duplicateProject(project)
                                } label: {
                                    Label("Duplicate Project", systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deleteProject(project)
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .withAppWallpaper()
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search in \(folder.name)...")
        .navigationTitle("\(folder.displayIcon) \(folder.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        showingAddProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                            .padding(7)
                            .background(Color(.systemBackground).opacity(0.65))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Menu {
                        Button {
                            showingEditFolderSheet = true
                        } label: {
                            Label("Edit Field", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteFolderConfirmation = true
                        } label: {
                            Label("Delete Field", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                            .padding(7)
                            .background(Color(.systemBackground).opacity(0.65))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditFolderSheet) {
            FieldEditModalView(
                folderToEdit: folder,
                onSaved: { updatedFolder in
                    self.folder = updatedFolder
                    Task { await loadProjects() }
                },
                onDeleted: {
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingAddProjectSheet) {
            QuickNewProjectView(presetFolderId: folder.id, folderName: folder.name) {
                Task { await loadProjects() }
            }
        }
        .confirmationDialog("Delete Field?", isPresented: $showDeleteFolderConfirmation, titleVisibility: .visible) {
            Button("Delete Field & All Projects", role: .destructive) {
                deleteEntireFolder()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deleting '\(folder.name)' will remove all projects inside it. This cannot be undone.")
        }
        .refreshable {
            await loadProjects()
        }
        .task {
            await loadProjects()
        }
    }

    private func loadProjects() async {
        do {
            let fetched = try await sync.fetchProjects(folderId: folder.id)
            await MainActor.run {
                self.projects = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func deleteProject(_ project: ProjectSummary) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation {
            projects.removeAll { $0.id == project.id }
        }
        Task {
            try? await sync.deleteProject(id: project.id)
        }
    }

    private func deleteEntireFolder() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
        Task {
            try? await sync.deleteFolder(id: folder.id)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func duplicateProject(_ project: ProjectSummary) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        Task {
            if let dup = try? await sync.duplicateProject(projectId: project.id) {
                await MainActor.run {
                    self.projects.insert(
                        ProjectSummary(
                            id: dup.id,
                            folderId: dup.folderId,
                            title: dup.title,
                            status: dup.status,
                            version: dup.version,
                            nextAction: dup.activeMilestones.first?.title,
                            updatedAt: Date()
                        ),
                        at: 0
                    )
                }
            }
        }
    }
}

// MARK: - Project Row Card (Full Width Floating Glass)
struct ProjectRowCard: View {
    let project: ProjectSummary
    var folderColor: String = "#3B82F6"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: folderColor))
                    .frame(width: 8, height: 8)

                Text(project.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                Text("v\(project.version)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.systemBackground).opacity(0.8))
                    .clipShape(Capsule())
            }

            if let next = project.nextAction, !next.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(next)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                    Text("Needs next action")
                        .font(.caption2)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.72))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Quick New Project Modal (Multi-Step Creation)
struct QuickNewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync = SyncService.shared

    var presetFolderId: String? = nil
    var folderName: String? = nil
    var onCreated: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var currentState: String = ""
    @State private var milestones: [String] = [""]
    @State private var selectedFolderId: String = ""
    @State private var availableFolders: [FolderBento] = []
    @State private var isCreating: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Project Identity
                Section("Project Details") {
                    TextField("Project Title (e.g. Redesign Landing)", text: $title)
                        .autocapitalization(.sentences)

                    if presetFolderId == nil {
                        Picker("Field", selection: $selectedFolderId) {
                            ForEach(availableFolders) { f in
                                Text("\(f.displayIcon) \(f.name)").tag(f.id)
                            }
                        }
                    } else if let fname = folderName {
                        HStack {
                            Text("Field")
                            Spacer()
                            Text(fname).foregroundColor(.secondary)
                        }
                    }
                }

                // Section 2: Quick Workflow Templates
                Section("Workflow Starter Template") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            templateButton("🚀 Feature Sprint") {
                                applyTemplate(["Design architecture", "Implement backend logic", "Build user interface", "Test & deploy"])
                            }

                            templateButton("🐛 Bug Fix") {
                                applyTemplate(["Reproduce issue", "Write regression test", "Apply fix", "Verify in staging"])
                            }

                            templateButton("📋 General Task") {
                                applyTemplate(["Scope requirements", "Execute plan", "Review outcome"])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Section 3: Current State of Affairs
                Section("Current State of Affairs (Optional)") {
                    TextField("What is the current situation?", text: $currentState, axis: .vertical)
                        .lineLimit(3...5)
                }

                // Section 4: Next Actions (Multi-step)
                Section(header: Text("Next Actions (Sequential)")) {
                    ForEach(Array(milestones.indices), id: \.self) { i in
                        HStack {
                            Text("\(i + 1).")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            TextField("Step \(i + 1) description", text: Binding(
                                get: { milestones.indices.contains(i) ? milestones[i] : "" },
                                set: { if milestones.indices.contains(i) { milestones[i] = $0 } }
                            ))
                            if milestones.count > 1 {
                                Button(action: {
                                    if milestones.indices.contains(i) {
                                        milestones.remove(at: i)
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(action: {
                        milestones.append("")
                    }) {
                        Label("Add Another Step", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .fontWeight(.bold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .task {
                if let pId = presetFolderId {
                    selectedFolderId = pId
                } else {
                    if let folders = try? await sync.fetchBento() {
                        self.availableFolders = folders
                        if let first = folders.first {
                            self.selectedFolderId = first.id
                        }
                    }
                }
            }
        }
    }

    private func templateButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        }) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemBackground))
                .foregroundColor(.primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func applyTemplate(_ steps: [String]) {
        self.milestones = steps
    }

    private func createProject() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let targetFolderId = presetFolderId ?? selectedFolderId
        guard !targetFolderId.isEmpty else { return }

        isCreating = true
        let validMilestones = milestones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        Task {
            do {
                _ = try await sync.createProject(
                    folderId: targetFolderId,
                    title: trimmedTitle,
                    currentState: currentState.trimmingCharacters(in: .whitespacesAndNewlines),
                    milestones: validMilestones
                )
                await MainActor.run {
                    isCreating = false
                    dismiss()
                    onCreated?()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    dismiss()
                    onCreated?()
                }
            }
        }
    }
}
