import Foundation
import Combine

public class SyncService: ObservableObject {
    public static let shared = SyncService()
    
    private let cacheKey = "state_next_ios_bento_cache"
    
    @Published public var serverBaseURL: String {
        didSet {
            UserDefaults.standard.set(serverBaseURL, forKey: "state_next_server_url")
        }
    }
    
    @Published public var isOnline: Bool = true
    @Published public var isSyncing: Bool = false
    @Published public var pendingSyncCount: Int = 0
    @Published public var syncConflictAlert: String? = nil
    @Published public var lastSyncTime: Date? = nil

    private let stagedQueueKey = "state_next_staged_queue"
    private var stagedQueue: [StagedSyncChange] = []

    public init() {
        let savedUrl = UserDefaults.standard.string(forKey: "state_next_server_url")
        self.serverBaseURL = savedUrl ?? "https://project-manager-app-78c6297c8f8b.herokuapp.com"
        loadStagedQueue()
    }

    // MARK: - Live API Calls

    /// Fetches live Bento folders with recent project previews
    @MainActor
    public func fetchBento() async throws -> [FolderBento] {
        isSyncing = true
        defer { isSyncing = false }
        
        guard let url = URL(string: "\(serverBaseURL)/api/bento") else {
            throw URLError(.badURL)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let folders = try JSONDecoder.apiDecoder.decode([FolderBento].self, from: data)
            self.isOnline = true
            self.lastSyncTime = Date()
            
            // Cache locally for offline availability
            if let encoded = try? JSONEncoder.apiEncoder.encode(folders) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }
            
            return folders
        } catch {
            self.isOnline = false
            // Fallback to local cache if offline
            if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
               let cachedFolders = try? JSONDecoder.apiDecoder.decode([FolderBento].self, from: cachedData) {
                return cachedFolders
            }
            throw error
        }
    }

    // MARK: - Folders / Fields API

    /// Creates a new Field/Folder
    public func createFolder(name: String, icon: String, color: String, order: Int = 0) async throws -> FolderBento {
        guard let url = URL(string: "\(serverBaseURL)/api/folders") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "icon": icon, "color": color, "order": order]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.apiDecoder.decode(FolderBento.self, from: data)
    }

    /// Updates existing Field/Folder
    public func updateFolder(id: String, name: String? = nil, icon: String? = nil, color: String? = nil, order: Int? = nil) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/folders/\(id)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let n = name { body["name"] = n }
        if let i = icon { body["icon"] = i }
        if let c = color { body["color"] = c }
        if let o = order { body["order"] = o }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Deletes a Field/Folder
    public func deleteFolder(id: String) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/folders/\(id)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Projects API

    /// Fetches project detail with active and archived milestones
    public func fetchProject(id: String) async throws -> ProjectDetail {
        guard let url = URL(string: "\(serverBaseURL)/api/projects/\(id)") else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder.apiDecoder.decode(ProjectDetail.self, from: data)
    }

    /// Fetches projects optionally filtered by status (e.g. "completed" for finished archive)
    public func fetchProjects(status: String? = nil, folderId: String? = nil) async throws -> [ProjectSummary] {
        var components = URLComponents(string: "\(serverBaseURL)/api/projects")
        var queryItems: [URLQueryItem] = []
        if let s = status { queryItems.append(URLQueryItem(name: "status", value: s)) }
        if let f = folderId { queryItems.append(URLQueryItem(name: "folder_id", value: f)) }
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        
        guard let url = components?.url else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder.apiDecoder.decode([ProjectSummary].self, from: data)
    }

    /// Creates a new project in a folder
    public func createProject(folderId: String, title: String, currentState: String = "", milestones: [String] = []) async throws -> ProjectDetail {
        guard let url = URL(string: "\(serverBaseURL)/api/projects") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "folder_id": folderId,
            "title": title,
            "current_state": currentState,
            "status": "active"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let proj = try JSONDecoder.apiDecoder.decode(ProjectDetail.self, from: data)
        
        // Sequentially create any initial milestones if provided
        for step in milestones {
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                _ = try? await createMilestone(projectId: proj.id, title: trimmed)
            }
        }
        
        return proj
    }

    /// Updates project properties (title, current_state, folder_id, status)
    public func updateProject(id: String, title: String? = nil, currentState: String? = nil, folderId: String? = nil, status: String? = nil) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/projects/\(id)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [:]
        if let t = title { body["title"] = t }
        if let s = currentState { body["current_state"] = s }
        if let f = folderId { body["folder_id"] = f }
        if let st = status { body["status"] = st }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Updates project current state of affairs
    public func updateProjectState(id: String, currentState: String) async throws {
        try await updateProject(id: id, currentState: currentState)
    }

    /// Toggles project status (e.g. "active" <-> "completed")
    public func toggleProjectStatus(id: String, status: String) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/projects/\(id)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["status": status]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Deletes a project
    public func deleteProject(id: String) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/projects/\(id)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Creates a new milestone for a project
    public func createMilestone(projectId: String, title: String) async throws -> MilestoneItem {
        guard var components = URLComponents(string: "\(serverBaseURL)/api/milestones") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "project_id", value: projectId)]
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "title": title,
            "is_completed": false,
            "order": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder.apiDecoder.decode(MilestoneItem.self, from: data)
    }

    /// Toggles milestone completion state
    public func toggleMilestone(milestoneId: String, isCompleted: Bool) async throws -> MilestoneItem {
        guard let url = URL(string: "\(serverBaseURL)/api/milestones/\(milestoneId)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "is_completed": isCompleted
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder.apiDecoder.decode(MilestoneItem.self, from: data)
    }

    /// Updates milestone title or order
    public func updateMilestone(milestoneId: String, title: String? = nil, order: Int? = nil) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/milestones/\(milestoneId)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [:]
        if let t = title { body["title"] = t }
        if let o = order { body["order"] = o }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Deletes a milestone
    public func deleteMilestone(milestoneId: String) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/milestones/\(milestoneId)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Reorders active milestones by updating their sequential orders
    public func reorderMilestones(milestones: [MilestoneItem]) async {
        for (index, m) in milestones.enumerated() {
            try? await updateMilestone(milestoneId: m.id, order: index)
        }
    }

    /// Duplicates an existing project with its active milestones
    public func duplicateProject(projectId: String) async throws -> ProjectDetail {
        let source = try await fetchProject(id: projectId)
        let newProject = try await createProject(
            folderId: source.folderId,
            title: "\(source.title) (Copy)",
            currentState: source.currentState
        )
        for m in source.activeMilestones {
            _ = try? await createMilestone(projectId: newProject.id, title: m.title)
        }
        return try await fetchProject(id: newProject.id)
    }

    // MARK: - Offline Staged Queue & Conflict Engine

    private func saveStagedQueue() {
        if let encoded = try? JSONEncoder.apiEncoder.encode(stagedQueue) {
            UserDefaults.standard.set(encoded, forKey: stagedQueueKey)
        }
    }

    private func loadStagedQueue() {
        if let data = UserDefaults.standard.data(forKey: stagedQueueKey),
           let saved = try? JSONDecoder.apiDecoder.decode([StagedSyncChange].self, from: data) {
            self.stagedQueue = saved
            self.pendingSyncCount = saved.count
        }
    }

    public func stageProjectUpdate(projectId: String, baseVersion: Int, title: String?, state: String?) {
        var payload: [String: String] = [:]
        if let t = title { payload["title"] = t }
        if let s = state { payload["current_state"] = s }

        let change = StagedSyncChange(
            entityType: "project",
            entityId: projectId,
            action: "update",
            baseVersion: baseVersion,
            payload: payload
        )
        stagedQueue.append(change)
        saveStagedQueue()
        pendingSyncCount = stagedQueue.count
        triggerSync()
    }

    public func stageMilestoneCompletion(milestoneId: String, isCompleted: Bool) {
        let change = StagedSyncChange(
            entityType: "milestone",
            entityId: milestoneId,
            action: "update",
            baseVersion: nil,
            payload: ["is_completed": isCompleted ? "true" : "false"]
        )
        stagedQueue.append(change)
        saveStagedQueue()
        pendingSyncCount = stagedQueue.count
        triggerSync()
    }

    public func stageMilestoneCreation(id: String, projectId: String, title: String) {
        let change = StagedSyncChange(
            entityType: "milestone",
            entityId: id,
            action: "create",
            baseVersion: nil,
            payload: ["project_id": projectId, "title": title, "is_completed": "false"]
        )
        stagedQueue.append(change)
        saveStagedQueue()
        pendingSyncCount = stagedQueue.count
        triggerSync()
    }

    public func triggerSync() {
        guard !stagedQueue.isEmpty else { return }
        guard let url = URL(string: "\(serverBaseURL)/api/sync") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": "ios_device_app",
            "changes": stagedQueue.map { [
                "entity_type": $0.entityType,
                "entity_id": $0.entityId,
                "action": $0.action,
                "base_version": $0.baseVersion as Any,
                "payload": $0.payload
            ]}
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let _ = error {
                    self.isOnline = false
                    return
                }

                self.isOnline = true
                guard let data = data else { return }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let conflicts = json["conflicts"] as? [[String: Any]], !conflicts.isEmpty {
                        self.syncConflictAlert = "Sync Conflict detected on \(conflicts.count) item(s). Changes were saved on server by another device."
                    } else {
                        self.stagedQueue.removeAll()
                        self.saveStagedQueue()
                        self.pendingSyncCount = 0
                        self.lastSyncTime = Date()
                    }
                }
            }
        }.resume()
    }
}

