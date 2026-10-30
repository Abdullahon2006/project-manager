import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FolderProjectsListView: View {
    let folder: FolderBento
    @ObservedObject var sync = SyncService.shared

    @State private var projects: [ProjectSummary] = []
    @State private var isLoading: Bool = true
    @State private var selectedStatus: ProjectFilter = .active
    @State private var showingAddProjectSheet: Bool = false
    @State private var errorMessage: String? = nil

    enum ProjectFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case completed = "Finished"
        var id: String { rawValue }
    }

    var filteredProjects: [ProjectSummary] {
        switch selectedStatus {
        case .active:
            return projects.filter { $0.status == "active" }
        case .completed:
            return projects.filter { $0.status == "completed" }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter Picker
            Picker("Filter", selection: $selectedStatus) {
                ForEach(ProjectFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

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
                    Text(folder.icon)
                        .font(.system(size: 48))
                    Text(selectedStatus == .active ? "No Active Projects" : "No Completed Projects")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(selectedStatus == .active ? "Tap + below to create a project in this folder." : "Finished projects will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredProjects) { project in
                        NavigationLink(destination: ProjectDetailView(projectId: project.id, initialTitle: project.title)) {
                            ProjectRowView(project: project)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteProject(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("\(folder.icon) \(folder.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddProjectSheet = true }) {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingAddProjectSheet) {
            QuickNewProjectView(presetFolderId: folder.id, folderName: folder.name) {
                Task { await loadProjects() }
            }
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
}

// MARK: - Project Row Component

struct ProjectRowView: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Text("v\(project.version)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let next = project.nextAction, !next.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(next)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick New Project Modal

struct QuickNewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync = SyncService.shared

    var presetFolderId: String? = nil
    var folderName: String? = nil
    var onCreated: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var currentState: String = ""
    @State private var firstMilestone: String = ""
    @State private var selectedFolderId: String = ""
    @State private var availableFolders: [FolderBento] = []
    @State private var isCreating: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Project Title (e.g. Redesign Landing)", text: $title)
                        .autocapitalization(.sentences)

                    if presetFolderId == nil {
                        Picker("Folder", selection: $selectedFolderId) {
                            ForEach(availableFolders) { f in
                                Text("\(f.icon) \(f.name)").tag(f.id)
                            }
                        }
                    } else if let fname = folderName {
                        HStack {
                            Text("Folder")
                            Spacer()
                            Text(fname).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Current State of Affairs (Optional)") {
                    TextField("What is the current situation?", text: $currentState, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("First Next Action (Optional)") {
                    TextField("Immediate first step to take", text: $firstMilestone)
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

    private func createProject() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let folderId = presetFolderId ?? selectedFolderId
        guard !folderId.isEmpty else { return }

        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        isCreating = true

        Task {
            do {
                let newProj = try await sync.createProject(
                    folderId: folderId,
                    title: trimmedTitle,
                    currentState: currentState.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                // If first milestone provided, create it immediately
                let trimmedM = firstMilestone.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedM.isEmpty {
                    _ = try? await sync.createMilestone(projectId: newProj.id, title: trimmedM)
                }

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
