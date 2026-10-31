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
    @State private var allFolders: [FolderBento] = []

    // Title editing
    @State private var editableTitle: String = ""
    @State private var isEditingTitle: Bool = false

    // State of Affairs & Auto-save
    @State private var currentStateText: String = ""
    @State private var isSavingState: Bool = false
    @State private var stateSaveTask: Task<Void, Never>? = nil

    // New action input & quick tags
    @State private var newMilestoneTitle: String = ""
    @FocusState private var isNewActionFocused: Bool

    // Modals & Sheets
    @State private var isArchiveExpanded: Bool = false
    @State private var isLoading: Bool = true
    @State private var showDeleteConfirmation: Bool = false
    @State private var editingMilestone: MilestoneItem? = nil
    @State private var editedMilestoneTitle: String = ""
    @State private var showShareSheet: Bool = false
    @State private var shareSummaryText: String = ""
    @State private var showCopiedAlert: Bool = false

    // Floating Undo Toast
    @State private var undoMilestone: MilestoneItem? = nil
    @State private var showUndoToast: Bool = false
    @State private var undoDismissTask: Task<Void, Never>? = nil

    // Quick tag chips for next actions
    let actionTags = ["⚡ Urgent", "🔥 Review", "📞 Call", "✉️ Email", "🛠️ Fix", "📝 Plan"]

    init(projectId: String, initialTitle: String = "Project") {
        self.projectId = projectId
        self.initialTitle = initialTitle
    }

    init(project: ProjectDetail) {
        self.projectId = project.id
        self.initialTitle = project.title
        _project = State(initialValue: project)
        _editableTitle = State(initialValue: project.title)
        _currentStateText = State(initialValue: project.currentState)
        _isLoading = State(initialValue: false)
    }

    // Computed Progress Metrics
    var totalActionsCount: Int {
        guard let p = project else { return 0 }
        return p.activeMilestones.count + p.archivedCount
    }

    var progressPercent: Int {
        guard totalActionsCount > 0, let p = project else { return 0 }
        return Int((Double(p.archivedCount) / Double(totalActionsCount)) * 100)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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
                        VStack(alignment: .leading, spacing: 20) {
                            
                            // 1. Header Bar: Status Badge, Folder Picker, Progress Capsule
                            headerSection(proj)
                            
                            // 2. Project Progress Bar
                            if totalActionsCount > 0 {
                                progressBarSection(proj)
                            }

                            // 3. Current State of Affairs (Auto-saving text box)
                            stateOfAffairsSection

                            // 4. Active Next Actions (Sequential with Reorder)
                            nextActionsSection(proj)

                            // 5. Packed Archive (Completed Milestones Accordion)
                            if proj.archivedCount > 0 || !proj.archivedMilestones.isEmpty {
                                packedArchiveSection(proj)
                            }

                            Divider()
                                .padding(.horizontal)

                            // 6. Project Actions (Finish / Reopen & Delete)
                            bottomActionsSection(proj)
                        }
                        .padding(.vertical)
                        .padding(.bottom, 80) // Spacing for floating undo toast
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

            // Floating Undo Toast
            if showUndoToast, let m = undoMilestone {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Completed \"\(m.title)\"")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: undoLastCompletedMilestone) {
                        Text("UNDO")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .withAppWallpaper()
        .navigationTitle(project?.title ?? initialTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: shareProjectSummary) {
                        Label("Share Summary", systemImage: "square.and.arrow.up")
                    }

                    Button(action: copySummaryToClipboard) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }

                    Button(action: duplicateCurrentProject) {
                        Label("Duplicate Project", systemImage: "plus.square.on.square")
                    }

                    Divider()

                    Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                        Label("Delete Project", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
            }
        }
        .refreshable {
            await loadProject()
        }
        .task {
            await loadProject()
            await loadFolders()
        }
        .sheet(item: $editingMilestone) { m in
            NavigationStack {
                Form {
                    Section("Edit Next Action") {
                        TextField("Action title", text: $editedMilestoneTitle)
                    }
                }
                .navigationTitle("Edit Action")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingMilestone = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveMilestoneTitle(m, newTitle: editedMilestoneTitle)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareSummaryText])
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

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(_ proj: ProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                StatusBadge(status: proj.status)
                
                Spacer()
                
                // Folder / Field Selector
                if !allFolders.isEmpty {
                    Menu {
                        ForEach(allFolders) { f in
                            Button {
                                moveProjectToFolder(f.id)
                            } label: {
                                HStack {
                                    Text("\(f.displayIcon) \(f.name)")
                                    if f.id == proj.folderId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentFolderName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }

                Text("v\(proj.version)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            // Project Title (Editable)
            HStack {
                if isEditingTitle {
                    TextField("Project Title", text: $editableTitle)
                        .font(.title2.weight(.bold))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveTitle() }

                    Button("Done") { saveTitle() }
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(proj.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)

                    Button {
                        editableTitle = proj.title
                        isEditingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func progressBarSection(_ proj: ProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Velocity Progress")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(proj.archivedCount)/\(totalActionsCount) completed (\(progressPercent)%)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(progressPercent == 100 ? .green : .blue)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(progressPercent == 100 ? Color.green : Color.blue)
                        .frame(width: max(0, min(geo.size.width * CGFloat(progressPercent) / 100.0, geo.size.width)), height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progressPercent)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var stateOfAffairsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Current State of Affairs", systemImage: "doc.text.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                Spacer()
                if isSavingState {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Saving...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Quick Template Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    TemplateChip(title: "+ Progress") {
                        appendTemplateText("\n• Progress: ")
                    }
                    TemplateChip(title: "+ Blocker") {
                        appendTemplateText("\n• Blocker: ")
                    }
                    TemplateChip(title: "+ Next") {
                        appendTemplateText("\n• Next: ")
                    }
                    TemplateChip(title: "⚡ Extract Actions") {
                        extractActionsFromState()
                    }
                }
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
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onChange(of: currentStateText) { newValue in
                        scheduleStateAutoSave(newValue)
                    }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func nextActionsSection(_ proj: ProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Next Actions (Sequential)", systemImage: "bolt.fill")
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

            // Quick Tag Chips for Action Title
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(actionTags, id: \.self) { tag in
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            if newMilestoneTitle.isEmpty {
                                newMilestoneTitle = "\(tag): "
                            } else {
                                newMilestoneTitle = "\(tag) " + newMilestoneTitle
                            }
                            isNewActionFocused = true
                        }) {
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Quick add next action input
            HStack(spacing: 10) {
                TextField("Add immediate next action...", text: $newMilestoneTitle)
                    .focused($isNewActionFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
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

            // List of active milestones with Reordering controls
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
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(proj.activeMilestones.enumerated()), id: \.element.id) { index, milestone in
                        ActiveMilestoneRow(
                            milestone: milestone,
                            index: index,
                            totalCount: proj.activeMilestones.count,
                            onToggle: { completeMilestone(milestone) },
                            onEdit: {
                                editingMilestone = milestone
                                editedMilestoneTitle = milestone.title
                            },
                            onDelete: { deleteMilestone(milestone) },
                            onMoveUp: { moveMilestoneUp(milestone) },
                            onMoveDown: { moveMilestoneDown(milestone) }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func packedArchiveSection(_ proj: ProjectDetail) -> some View {
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
                .background(.ultraThinMaterial)
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

    @ViewBuilder
    private func bottomActionsSection(_ proj: ProjectDetail) -> some View {
        VStack(spacing: 12) {
            Button(action: toggleProjectCompletion) {
                HStack {
                    Image(systemName: proj.status == "active" ? "checkmark.circle" : "arrow.uturn.backward.circle")
                    Text(proj.status == "active" ? "Mark Project as Finished" : "Reopen Active Stream")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(proj.status == "active" ? Color.green.opacity(0.18) : Color.blue.opacity(0.18))
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

    private var currentFolderName: String {
        guard let p = project else { return "Field" }
        if let match = allFolders.first(where: { $0.id == p.folderId }) {
            return "\(match.displayIcon) \(match.name)"
        }
        return "Field"
    }

    // MARK: - Actions & Sync Helpers

    private func loadProject() async {
        do {
            let detail = try await sync.fetchProject(id: projectId)
            await MainActor.run {
                self.project = detail
                self.editableTitle = detail.title
                self.currentStateText = detail.currentState
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func loadFolders() async {
        if let folders = try? await sync.fetchBento() {
            await MainActor.run {
                self.allFolders = folders
            }
        }
    }

    private func saveTitle() {
        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var p = project else {
            isEditingTitle = false
            return
        }
        isEditingTitle = false
        p.title = trimmed
        project = p

        Task {
            try? await sync.updateProject(id: p.id, title: trimmed)
        }
    }

    private func moveProjectToFolder(_ folderId: String) {
        guard var p = project, p.folderId != folderId else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        p.folderId = folderId
        project = p

        Task {
            try? await sync.updateProject(id: p.id, folderId: folderId)
        }
    }

    private func appendTemplateText(_ snippet: String) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        currentStateText += snippet
    }

    private func extractActionsFromState() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        let lines = currentStateText.components(separatedBy: .newlines)
        var extracted: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let clean = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty && clean.count > 3 {
                    extracted.append(clean)
                }
            } else if trimmed.lowercased().hasPrefix("next:") || trimmed.lowercased().hasPrefix("todo:") {
                let clean = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty {
                    extracted.append(clean)
                }
            }
        }

        guard !extracted.isEmpty else { return }
        for item in extracted {
            Task {
                if let created = try? await sync.createMilestone(projectId: projectId, title: item) {
                    await MainActor.run {
                        withAnimation {
                            project?.activeMilestones.append(created)
                        }
                    }
                }
            }
        }
    }

    private func scheduleStateAutoSave(_ text: String) {
        stateSaveTask?.cancel()
        stateSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled {
                await MainActor.run { isSavingState = true }
                do {
                    try await sync.updateProject(id: projectId, currentState: text)
                    await MainActor.run {
                        isSavingState = false
                        if var p = project {
                            p.currentState = text
                            p.version += 1
                            self.project = p
                        }
                    }
                } catch {
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

    private func moveMilestoneUp(_ milestone: MilestoneItem) {
        guard let idx = project?.activeMilestones.firstIndex(where: { $0.id == milestone.id }), idx > 0 else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation {
            project?.activeMilestones.swapAt(idx, idx - 1)
        }
        if let list = project?.activeMilestones {
            Task { await sync.reorderMilestones(milestones: list) }
        }
    }

    private func moveMilestoneDown(_ milestone: MilestoneItem) {
        guard let idx = project?.activeMilestones.firstIndex(where: { $0.id == milestone.id }),
              let count = project?.activeMilestones.count, idx < count - 1 else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation {
            project?.activeMilestones.swapAt(idx, idx + 1)
        }
        if let list = project?.activeMilestones {
            Task { await sync.reorderMilestones(milestones: list) }
        }
    }

    private func completeMilestone(_ milestone: MilestoneItem) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        // Trigger floating undo toast
        undoMilestone = milestone
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showUndoToast = true
        }
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation { showUndoToast = false }
                }
            }
        }

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

    private func undoLastCompletedMilestone() {
        guard let m = undoMilestone else { return }
        undoDismissTask?.cancel()
        withAnimation { showUndoToast = false }
        uncompleteMilestone(m)
        undoMilestone = nil
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

    private func saveMilestoneTitle(_ milestone: MilestoneItem, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingMilestone = nil
            return
        }
        editingMilestone = nil

        if let idx = project?.activeMilestones.firstIndex(where: { $0.id == milestone.id }) {
            project?.activeMilestones[idx].title = trimmed
        }

        Task {
            try? await sync.updateMilestone(milestoneId: milestone.id, title: trimmed)
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
            try? await sync.deleteMilestone(milestoneId: milestone.id)
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
            try? await sync.toggleProjectStatus(id: p.id, status: targetStatus)
        }
    }

    private func deleteEntireProject() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif

        Task {
            try? await sync.deleteProject(id: projectId)
            await MainActor.run { dismiss() }
        }
    }

    private func duplicateCurrentProject() {
        Task {
            if let dup = try? await sync.duplicateProject(projectId: projectId) {
                await MainActor.run {
                    self.project = dup
                    self.editableTitle = dup.title
                    self.currentStateText = dup.currentState
                }
            }
        }
    }

    private func generateMarkdownSummary() -> String {
        guard let p = project else { return "" }
        var md = "# \(p.title)\n"
        md += "**Field:** \(currentFolderName)\n"
        md += "**Status:** \(p.status.capitalized)\n\n"
        if !p.currentState.trimmingCharacters(in: .whitespaces).isEmpty {
            md += "## Current State of Affairs\n\(p.currentState)\n\n"
        }
        md += "## Next Actions\n"
        for m in p.activeMilestones {
            md += "- [ ] \(m.title)\n"
        }
        if !p.archivedMilestones.isEmpty {
            md += "\n## Completed Milestones\n"
            for m in p.archivedMilestones {
                md += "- [x] \(m.title)\n"
            }
        }
        return md
    }

    private func shareProjectSummary() {
        shareSummaryText = generateMarkdownSummary()
        showShareSheet = true
    }

    private func copySummaryToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = generateMarkdownSummary()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Subcomponents

struct TemplateChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ActiveMilestoneRow: View {
    let milestone: MilestoneItem
    let index: Int
    let totalCount: Int
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
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

            // Move Up/Down Controls
            HStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(index > 0 ? .primary : .secondary.opacity(0.2))
                        .padding(4)
                }
                .disabled(index == 0)
                .buttonStyle(.plain)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(index < totalCount - 1 ? .primary : .secondary.opacity(0.2))
                        .padding(4)
                }
                .disabled(index >= totalCount - 1)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(4)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial)
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
        .background(.ultraThinMaterial)
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

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
