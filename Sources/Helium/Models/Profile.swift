import Foundation

/// Represents a browser profile with isolated fingerprint and settings
struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var lastUsedAt: Date?
    var launchCount: Int
    
    // Organization
    var folderId: UUID?
    var tagIds: Set<UUID>
    var color: ProfileColor
    
    // Proxy binding
    var proxyId: UUID?
    
    // Fingerprint configuration
    var fingerprint: FingerprintConfig
    
    // Browser settings
    var userAgent: String?
    var startUrl: String
    var extensions: [BrowserExtension]
    
    // Status
    var status: ProfileStatus
    
    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        folderId: UUID? = nil,
        tagIds: Set<UUID> = [],
        color: ProfileColor = .blue,
        proxyId: UUID? = nil,
        fingerprint: FingerprintConfig = .random(),
        startUrl: String = "https://www.google.com",
        extensions: [BrowserExtension] = []
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = Date()
        self.lastUsedAt = nil
        self.launchCount = 0
        self.folderId = folderId
        self.tagIds = tagIds
        self.color = color
        self.proxyId = proxyId
        self.fingerprint = fingerprint
        self.userAgent = nil
        self.startUrl = startUrl
        self.extensions = extensions
        self.status = .ready
    }
}

// MARK: - Profile Status

enum ProfileStatus: String, Codable, Hashable {
    case ready = "Ready"
    case running = "Running"
    case syncing = "Syncing"
    case error = "Error"
    
    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .running: return "play.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .ready: return "green"
        case .running: return "blue"
        case .syncing: return "orange"
        case .error: return "red"
        }
    }
}

// MARK: - Profile Color

enum ProfileColor: String, Codable, CaseIterable, Hashable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
    
    var swiftUIColor: String {
        rawValue.capitalized
    }
}

// MARK: - Browser Extension

struct BrowserExtension: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var enabled: Bool
    
    init(id: UUID = UUID(), name: String, path: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.path = path
        self.enabled = enabled
    }
}
