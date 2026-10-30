import SwiftUI

struct FinishedArchiveView: View {
    @ObservedObject var sync = SyncService.shared
    @State private var finishedProjects: [ProjectSummary] = []
    @State private var isLoading: Bool = false
    @State private var searchQuery: String = ""
    @State private var errorMessage: String? = nil

    var filteredProjects: [ProjectSummary] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return finishedProjects
        }
        return finishedProjects.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        Group {
            if isLoading && finishedProjects.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading archive...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if finishedProjects.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Completed Projects Yet")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Projects you mark as finished will appear here in the packed archive.")
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
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.green)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.title)
                                        .font(.headline)
                                        .strikethrough(false)
                                        .foregroundColor(.primary)

                                    if let updated = project.updatedAt {
                                        Text("Completed \(updated, format: .dateTime.month().day().year())")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Button(action: { reopenProject(project) }) {
                                    Text("Reopen")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .searchable(text: $searchQuery, prompt: "Search finished archive...")
            }
        }
        .navigationTitle("Finished Archive")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadFinishedProjects()
        }
        .task {
            await loadFinishedProjects()
        }
    }

    private func loadFinishedProjects() async {
        isLoading = true
        errorMessage = nil
        do {
            let projects = try await sync.fetchProjects(status: "completed")
            await MainActor.run {
                self.finishedProjects = projects
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func reopenProject(_ project: ProjectSummary) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation {
            finishedProjects.removeAll { $0.id == project.id }
        }
        Task {
            do {
                try await sync.toggleProjectStatus(id: project.id, status: "active")
            } catch {
                await loadFinishedProjects()
            }
        }
    }
}
