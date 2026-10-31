import Foundation
import os

// MARK: - Fast & Thread-Safe Date Decoder & Encoder

public extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        
        let posixMicro: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            return df
        }()
        
        let posixSec: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return df
        }()
        
        let lock = os_unfair_lock_t.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let count = dateStr.utf8.count
            
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            
            // Fast-path branch routing based on length and markers
            if dateStr.contains("Z") || dateStr.contains("+") {
                if dateStr.contains(".") {
                    if let dt = isoFraction.date(from: dateStr) { return dt }
                }
                if let dt = isoStandard.date(from: dateStr) { return dt }
            } else if count >= 26 {
                if let dt = posixMicro.date(from: dateStr) { return dt }
            } else if count == 19 {
                if let dt = posixSec.date(from: dateStr) { return dt }
            }
            
            // Fallbacks
            if let dt = posixMicro.date(from: dateStr) { return dt }
            if let dt = isoFraction.date(from: dateStr) { return dt }
            if let dt = posixSec.date(from: dateStr) { return dt }
            if let dt = isoStandard.date(from: dateStr) { return dt }
            
            return Date()
        }
        return decoder
    }()
}

public extension JSONEncoder {
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - Data Models

public struct FolderBento: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var icon: String
    public var color: String
    public var order: Int
    public var projectCount: Int
    public var recentProjects: [ProjectSummary]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, order
        case projectCount = "project_count"
        case recentProjects = "recent_projects"
    }
    
    public init(id: String, name: String, icon: String, color: String, order: Int, projectCount: Int, recentProjects: [ProjectSummary]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.order = order
        self.projectCount = projectCount
        self.recentProjects = recentProjects
    }

    public var displayIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 2 && !trimmed.isEmpty { return trimmed }
        switch trimmed.lowercased() {
        case "folder", "default", "stream": return "📁"
        case "code", "coding", "terminal", "lightning", "bolt": return "⚡"
        case "palette", "art", "creative", "design": return "🎨"
        case "plant", "life", "sprout", "grow": return "🌱"
        case "science", "lab", "research", "microscope": return "🔬"
        case "briefcase", "work", "business": return "💼"
        case "rocket", "launch", "ship": return "🚀"
        case "book", "reading", "study", "notes": return "📚"
        case "tools", "wrench", "settings": return "🛠️"
        case "target", "goal", "focus": return "🎯"
        case "sparkles", "stars", "magic": return "✨"
        case "lightbulb", "idea": return "💡"
        case "phone", "mobile", "ios": return "📱"
        case "globe", "web", "internet": return "🌐"
        case "chart", "analytics", "stats": return "📊"
        case "lock", "security", "private": return "🔒"
        default: return "📁"
        }
    }
}

public struct ProjectSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let folderId: String
    public var title: String
    public var status: String
    public var version: Int
    public var nextAction: String?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, status, version
        case folderId = "folder_id"
        case nextAction = "next_action"
        case updatedAt = "updated_at"
    }
    
    public init(id: String, folderId: String, title: String, status: String, version: Int, nextAction: String? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.status = status
        self.version = version
        self.nextAction = nextAction
        self.updatedAt = updatedAt
    }
}

public struct ProjectDetail: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var folderId: String
    public var title: String
    public var currentState: String
    public var status: String
    public var version: Int
    public let createdAt: Date?
    public var updatedAt: Date?
    public var activeMilestones: [MilestoneItem]
    public var archivedMilestones: [MilestoneItem]
    public var archivedCount: Int
    public var archivedPreview: [MilestoneItem]

    enum CodingKeys: String, CodingKey {
        case id, title, status, version
        case folderId = "folder_id"
        case currentState = "current_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case activeMilestones = "active_milestones"
        case archivedMilestones = "archived_milestones"
        case archivedCount = "archived_count"
        case archivedPreview = "archived_preview"
    }
    
    public init(id: String, folderId: String, title: String, currentState: String, status: String, version: Int, createdAt: Date? = nil, updatedAt: Date? = nil, activeMilestones: [MilestoneItem] = [], archivedMilestones: [MilestoneItem] = [], archivedCount: Int = 0, archivedPreview: [MilestoneItem] = []) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.currentState = currentState
        self.status = status
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeMilestones = activeMilestones
        self.archivedMilestones = archivedMilestones
        self.archivedCount = archivedCount
        self.archivedPreview = archivedPreview
    }
}

public struct MilestoneItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectId: String?
    public var title: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var order: Int
    public var version: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, order, version
        case projectId = "project_id"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
    }
    
    public init(id: String, projectId: String? = nil, title: String, isCompleted: Bool, completedAt: Date? = nil, order: Int = 0, version: Int? = 1) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.order = order
        self.version = version
    }
}

// MARK: - Staged Change for Conflict-Controlled Sync

public struct StagedSyncChange: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let entityType: String
    public let entityId: String
    public let action: String
    public let baseVersion: Int?
    public let payload: [String: String]
    public let clientTimestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case entityId = "entity_id"
        case action
        case baseVersion = "base_version"
        case payload
        case clientTimestamp = "client_timestamp"
    }

    public init(id: String = UUID().uuidString, entityType: String, entityId: String, action: String, baseVersion: Int?, payload: [String: String], clientTimestamp: Date = Date()) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.baseVersion = baseVersion
        self.payload = payload
        self.clientTimestamp = clientTimestamp
    }
}

// MARK: - Sync Request & Response Schemas

public struct SyncRequest: Codable, Sendable {
    public let clientId: String
    public let changes: [StagedSyncChange]
    public let since: Date?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case changes
        case since
    }

    public init(clientId: String = "ios_device_app", changes: [StagedSyncChange], since: Date? = nil) {
        self.clientId = clientId
        self.changes = changes
        self.since = since
    }
}

public struct ConflictItem: Codable, Identifiable, Sendable {
    public var id: String { "\(entityType)_\(entityId)" }
    public let entityType: String
    public let entityId: String
    public let fieldConflicts: [String]
    public let clientPayload: [String: String]
    public let serverPayload: [String: String]
    public let serverVersion: Int

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case fieldConflicts = "field_conflicts"
        case clientPayload = "client_payload"
        case serverPayload = "server_payload"
        case serverVersion = "server_version"
    }
}

public struct SyncResponse: Codable, Sendable {
    public let success: Bool
    public let appliedCount: Int
    public let conflicts: [ConflictItem]
    public let serverTime: Date?

    enum CodingKeys: String, CodingKey {
        case success
        case appliedCount = "applied_count"
        case conflicts
        case serverTime = "server_time"
    }
}
