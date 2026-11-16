import SwiftUI

public struct DeadlinesListView: View {
    var sync: SyncService = SyncService.shared
    var searchQuery: String = ""
    var isActiveTab: Bool = false

    @State private var tasks: [TaskDeadlineItem] = []
    @State private var isLoading: Bool = false
    @State private var selectedFilter: DeadlineFilter = .all
    @State private var errorMessage: String? = nil

    private let cacheKey = "state_next_ios_deadlines_cache"

    public enum DeadlineFilter: String, CaseIterable, Identifiable {
        case all = "All Tasks"
        case dueOnly = "With Deadline"
        case overdue = "Overdue"
        var id: String { rawValue }
    }

    public init(sync: SyncService = SyncService.shared, searchQuery: String = "", isActiveTab: Bool = false) {
        self.sync = sync
        self.searchQuery = searchQuery
        self.isActiveTab = isActiveTab

        if let cachedData = UserDefaults.standard.data(forKey: "state_next_ios_deadlines_cache"),
           let cached = try? JSONDecoder.apiDecoder.decode([TaskDeadlineItem].self, from: cachedData) {
            _tasks = State(initialValue: cached)
        }
    }

    var filteredTasks: [TaskDeadlineItem] {
        var list = tasks

        switch selectedFilter {
        case .all:
            break
        case .dueOnly:
            list = list.filter { $0.deadline != nil }
        case .overdue:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            list = list.filter { task in
                guard let dl = task.deadline else { return false }
                return Calendar.current.startOfDay(for: dl) < startOfToday
            }
        }

        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter {
                $0.title.lowercased().contains(q) ||
                $0.projectTitle.lowercased().contains(q) ||
                $0.folderName.lowercased().contains(q)
            }
        }

        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DeadlineFilter.allCases) { filter in
                            DashboardFilterChip(
                                title: filter.rawValue,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if isLoading && tasks.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading deadlines...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if filteredTasks.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No Deadlines Found")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(selectedFilter == .overdue
                             ? "Great job! You have no overdue tasks."
                             : "Add target dates to your project tasks to track milestones here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTasks) { task in
                            deadlineTaskRow(task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            }
            .padding(.top, 4)
        }
        .refreshable {
            await loadDeadlines()
        }
        .onChange(of: isActiveTab) { active in
            if active {
                Task { await loadDeadlines() }
            }
        }
        .task {
            if isActiveTab || tasks.isEmpty {
                await loadDeadlines()
            }
        }
    }

    // MARK: - Task Row
    @ViewBuilder
    private func deadlineTaskRow(_ task: TaskDeadlineItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Checkmark button
            Button(action: { completeTask(task) }) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                NavigationLink(destination: ProjectDetailView(projectId: task.projectId, initialTitle: task.projectTitle)) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: task.folderColor))
                            .frame(width: 6, height: 6)

                        Text("\(task.folderName) / \(task.projectTitle)")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Deadline badge
            if let dl = task.deadline {
                let overdue = isOverdue(dl)
                HStack(spacing: 4) {
                    Image(systemName: overdue ? "exclamationmark.triangle.fill" : "calendar")
                        .font(.system(size: 10))
                    Text(formatDeadline(dl))
                        .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(overdue ? Color.red.opacity(0.14) : Color.blue.opacity(0.12))
                .foregroundColor(overdue ? .red : .blue)
                .clipShape(Capsule())
            } else {
                Text("No date")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
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

    // MARK: - Helpers
    private func completeTask(_ task: TaskDeadlineItem) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            tasks.removeAll { $0.id == task.id }
        }
        saveCache(tasks)

        Task {
            _ = try? await sync.toggleMilestone(milestoneId: task.id, isCompleted: true)
        }
    }

    private func loadDeadlines() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await sync.fetchDeadlines(status: "active")
            await MainActor.run {
                withAnimation {
                    self.tasks = fetched
                }
                saveCache(fetched)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCache(_ items: [TaskDeadlineItem]) {
        if let encoded = try? JSONEncoder.apiEncoder.encode(items) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }

    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return target < today
    }

    private func formatDeadline(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: today, to: target).day ?? 0

        if diff < 0 {
            return "Overdue \(abs(diff))d"
        } else if diff == 0 {
            return "Today"
        } else if diff == 1 {
            return "Tomorrow"
        } else if diff <= 7 {
            return "In \(diff)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
