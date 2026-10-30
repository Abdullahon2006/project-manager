import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProjectDetailView: View {
    let projectId: String
    var initialTitle: String = "Project"

    @StateObject private var sync = SyncService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var project: ProjectDetail? = nil
    @State private var currentStateText: String = ""
    @State private var newMilestoneTitle: String = ""
    @State private var isArchiveExpanded: Bool = false
    @State private var isLoading: Bool = true
    @State private var isSavingState: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var errorMessage: String? = nil

    @State private var stateSaveTask: Task<Void, Never>? = nil

    init(projectId: String, initialTitle: String = "Project") {
        self.projectId = projectId
        self.initialTitle = initialTitle
    }

    // Convenience initializer for direct previews or parent model passing
    init(project: ProjectDetail) {
        self.projectId = project.id
        self.initialTitle = project.title
        _project = State(initialValue: project)
        _currentStateText = State(initialValue: project.currentState)
        _isLoading = State(initialValue: false)
    }

    var body: some View {
        Group {
            if isLoading && project == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading workspace...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let proj = project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        
                        // Header Status & Meta Bar
                        HStack(alignment: .center) {
                            StatusBadge(status: proj.status)
                            Spacer()
                            if isSavingState {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Saving...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("v\(proj.version)")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(.tertiarySystemBackground))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)

                        // 1. Current State of Affairs (Auto-saving text box)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Current State of Affairs", systemImage: "doc.text.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .textCase(.uppercase)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: "mic.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue.opacity(0.8))
                            }

                            ZStack(alignment: .topLeading) {
                                if currentStateText.isEmpty {
                                    Text("Describe current project reality, progress, or open questions...")
                                        .font(.body)
                                        .foregroundColor(.secondary.opacity(0.6))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                }
                                TextEditor(text: $currentStateText)
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                    )
                                    .onChange(of: currentStateText) { newValue in
                                        scheduleStateAutoSave(newValue)
                                    }
                            }
                        }
                        .padding(.horizontal)

                        // 2. Active Next Actions
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Next Actions", systemImage: "bolt.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .textCase(.uppercase)
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("\(proj.activeMilestones.count) open")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)

                            // Quick add next action input
                            HStack(spacing: 10) {
                                TextField("Add immediate next action...", text: $newMilestoneTitle)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .onSubmit {
                                        createNextAction()
                                    }

                                Button(action: createNextAction) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(newMilestoneTitle.trimmingCharacters(in: .whitespaces).isEmpty ? .gray.opacity(0.4) : .blue)
                                }
                                .disabled(newMilestoneTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(.horizontal)

                            // List of active milestones
                            if proj.activeMilestones.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 6) {
                                        Image(systemName: "checkmark.seal")
                                            .font(.title2)
                                            .foregroundColor(.green.opacity(0.7))
                                        Text("All actions clear! Add what's next.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 14)
                                    Spacer()
                                }
                                .background(Color(.secondarySystemBackground).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(proj.activeMilestones) { milestone in
                                        ActiveMilestoneRow(
                                            milestone: milestone,
                                            onToggle: { completeMilestone(milestone) },
                                            onDelete: { deleteMilestone(milestone) }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // 3. Packed Archive (Completed Milestones Accordion)
                        if proj.archivedCount > 0 || !proj.archivedMilestones.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isArchiveExpanded.toggle()
                                    }
                                }) {
                                    HStack {
                                        Label("Packed Archive (\(proj.archivedCount))", systemImage: "archivebox.fill")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .textCase(.uppercase)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: isArchiveExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                if isArchiveExpanded {
                                    VStack(spacing: 8) {
                                        ForEach(proj.archivedMilestones) { item in
                                            ArchivedMilestoneRow(milestone: item) {
                                                uncompleteMilestone(item)
                                            } onDelete: {
                                                deleteMilestone(item)
                                            }
                                        }
                                    }
                                } else {
                                    // Preview top 2 archived items
                                    VStack(spacing: 6) {
                                        ForEach(proj.archivedPreview) { item in
                                            HStack(spacing: 8) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary.opacity(0.7))
                                                Text(item.title)
                                                    .font(.caption)
                                                    .strikethrough()
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                if let date = item.completedAt {
                                                    Text(date, format: .dateTime.month().day())
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary.opacity(0.7))
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Divider()
                            .padding(.horizontal)

                        // 4. Project Actions (Finish / Reopen & Delete)
                        VStack(spacing: 12) {
                            Button(action: toggleProjectCompletion) {
                                HStack {
                                    Image(systemName: proj.status == "active" ? "checkmark.circle" : "arrow.uturn.backward.circle")
                                    Text(proj.status == "active" ? "Mark Project as Finished" : "Reopen Active Stream")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(proj.status == "active" ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                                .foregroundColor(proj.status == "active" ? .green : .blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button(action: { showDeleteConfirmation = true }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Project")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    .padding(.vertical)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Project not found.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await loadProject() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(project?.title ?? initialTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadProject()
        }
        .task {
            await loadProject()
        }
        .confirmationDialog("Delete Project?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) {
                deleteEntireProject()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete '\(project?.title ?? "this project")' and all its milestones.")
        }
    }

    // MARK: - Actions & Sync Helpers

    private func loadProject() async {
        do {
            let detail = try await sync.fetchProject(id: projectId)
            await MainActor.run {
                self.project = detail
                self.currentStateText = detail.currentState
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func scheduleStateAutoSave(_ text: String) {
        stateSaveTask?.cancel()
        stateSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000) // 700ms debounce
            if !Task.isCancelled {
                await MainActor.run { isSavingState = true }
                do {
                    try await sync.updateProjectState(id: projectId, currentState: text)
                    await MainActor.run {
                        isSavingState = false
                        if var p = project {
                            p.currentState = text
                            p.version += 1
                            self.project = p
                        }
                    }
                } catch {
                    // Fallback to staged queue if offline
                    if let p = project {
                        sync.stageProjectUpdate(projectId: p.id, baseVersion: p.version, title: nil, state: text)
                    }
                    await MainActor.run { isSavingState = false }
                }
            }
        }
    }

    private func createNextAction() {
        let trimmed = newMilestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        newMilestoneTitle = ""

        Task {
            do {
                let created = try await sync.createMilestone(projectId: projectId, title: trimmed)
                await MainActor.run {
                    withAnimation {
                        project?.activeMilestones.append(created)
                        project?.version += 1
                    }
                }
            } catch {
                // Optimistic local add and staged queue
                let localId = UUID().uuidString
                let tempMilestone = MilestoneItem(
                    id: localId,
                    projectId: projectId,
                    title: trimmed,
                    isCompleted: false,
                    order: (project?.activeMilestones.count ?? 0) + 1
                )
                await MainActor.run {
                    withAnimation {
                        project?.activeMilestones.append(tempMilestone)
                    }
                }
                sync.stageMilestoneCreation(id: localId, projectId: projectId, title: trimmed)
            }
        }
    }

    private func completeMilestone(_ milestone: MilestoneItem) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        withAnimation(.easeInOut(duration: 0.25)) {
            project?.activeMilestones.removeAll { $0.id == milestone.id }
            var completed = milestone
            completed.isCompleted = true
            completed.completedAt = Date()
            project?.archivedMilestones.insert(completed, at: 0)
            project?.archivedPreview.insert(completed, at: 0)
            project?.archivedCount += 1
            project?.version += 1
        }

        Task {
            do {
                _ = try await sync.toggleMilestone(milestoneId: milestone.id, isCompleted: true)
            } catch {
                sync.stageMilestoneCompletion(milestoneId: milestone.id, isCompleted: true)
            }
        }
    }

    private func uncompleteMilestone(_ milestone: MilestoneItem) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        withAnimation(.easeInOut(duration: 0.25)) {
            project?.archivedMilestones.removeAll { $0.id == milestone.id }
            project?.archivedPreview.removeAll { $0.id == milestone.id }
            if let count = project?.archivedCount, count > 0 {
                project?.archivedCount = count - 1
            }
            var reopened = milestone
            reopened.isCompleted = false
            reopened.completedAt = nil
            project?.activeMilestones.append(reopened)
            project?.version += 1
        }

        Task {
            do {
                _ = try await sync.toggleMilestone(milestoneId: milestone.id, isCompleted: false)
            } catch {
                sync.stageMilestoneCompletion(milestoneId: milestone.id, isCompleted: false)
            }
        }
    }

    private func deleteMilestone(_ milestone: MilestoneItem) {
        withAnimation {
            project?.activeMilestones.removeAll { $0.id == milestone.id }
            project?.archivedMilestones.removeAll { $0.id == milestone.id }
            project?.archivedPreview.removeAll { $0.id == milestone.id }
            if milestone.isCompleted, let count = project?.archivedCount, count > 0 {
                project?.archivedCount = count - 1
            }
        }

        Task {
            do {
                try await sync.deleteMilestone(milestoneId: milestone.id)
            } catch {
                // If offline, staged delete
            }
        }
    }

    private func toggleProjectCompletion() {
        guard let p = project else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        let targetStatus = (p.status == "active") ? "completed" : "active"
        withAnimation {
            project?.status = targetStatus
            project?.version += 1
        }

        Task {
            do {
                try await sync.toggleProjectStatus(id: p.id, status: targetStatus)
            } catch {
                sync.stageProjectUpdate(projectId: p.id, baseVersion: p.version, title: nil, state: nil)
            }
        }
    }

    private func deleteEntireProject() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif

        Task {
            do {
                try await sync.deleteProject(id: projectId)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { dismiss() }
            }
        }
    }
}

// MARK: - Subcomponents

struct ActiveMilestoneRow: View {
    let milestone: MilestoneItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Text(milestone.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ArchivedMilestoneRow: View {
    let milestone: MilestoneItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)

            Text(milestone.title)
                .font(.subheadline)
                .strikethrough()
                .foregroundColor(.secondary)

            Spacer()

            if let date = milestone.completedAt {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status == "active" ? Color.blue : Color.green)
                .frame(width: 6, height: 6)
            Text(status == "active" ? "Active Stream" : "Completed")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status == "active" ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
        .foregroundColor(status == "active" ? .blue : .green)
        .clipShape(Capsule())
    }
}
