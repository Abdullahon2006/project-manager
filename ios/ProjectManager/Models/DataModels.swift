import Foundation

// MARK: - API Date Decoder & Encoder

public extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let formatterStandard = ISO8601DateFormatter()
        formatterStandard.formatOptions = [.withInternetDateTime]
        
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        
        let fallbackNoFrac = DateFormatter()
        fallbackNoFrac.locale = Locale(identifier: "en_US_POSIX")
        fallbackNoFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let dateStr = try container.decode(String.self)
            
            if let date = formatterWithFraction.date(from: dateStr) {
                return date
            }
            if let date = fallbackFormatter.date(from: dateStr) {
                return date
            }
            if let date = formatterStandard.date(from: dateStr) {
                return date
            }
            if let date = fallbackNoFrac.date(from: dateStr) {
                return date
            }
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

public struct FolderBento: Codable, Identifiable, Hashable {
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
        default:
            // If it's already an emoji or short symbol, return it as-is
            if trimmed.count <= 2 { return trimmed }
            return "📁"
        }
    }
}

public struct ProjectSummary: Codable, Identifiable, Hashable {
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

public struct ProjectDetail: Codable, Identifiable {
    public let id: String
    public var folderId: String
    public var title: String
    public var currentState: String
    public var status: String
    public var version: Int
    public var createdAt: Date?
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

public struct MilestoneItem: Codable, Identifiable, Hashable {
    public let id: String
    public var projectId: String?
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
public struct StagedSyncChange: Codable {
    public let entityType: String
    public let entityId: String
    public let action: String
    public let baseVersion: Int?
    public let payload: [String: String]
    public let clientTimestamp: Date
    
    public init(entityType: String, entityId: String, action: String, baseVersion: Int?, payload: [String : String], clientTimestamp: Date = Date()) {
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.baseVersion = baseVersion
        self.payload = payload
        self.clientTimestamp = clientTimestamp
    }
}
