import SwiftUI

struct FinishedArchiveView: View {
    @ObservedObject var sync = SyncService.shared
    var searchQuery: String = ""
    @State private var finishedProjects: [ProjectSummary] = []
    @State private var isLoading: Bool = false
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
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
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
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredProjects) { project in
                            NavigationLink(destination: ProjectDetailView(projectId: project.id, initialTitle: project.title)) {
                                HStack(alignment: .center, spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.green)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(project.title)
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
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
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
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
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
            }
        }
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
