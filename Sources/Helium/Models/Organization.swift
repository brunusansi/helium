import Foundation

/// Tag for organizing profiles and proxies
struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: TagColor
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, color: TagColor = .blue) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
    }
}

enum TagColor: String, Codable, CaseIterable, Hashable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, gray
    
    var swiftUIColor: String {
        rawValue.capitalized
    }
}

/// Folder for organizing profiles
struct Folder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var parentId: UUID?
    var createdAt: Date
    var sortOrder: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        parentId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.parentId = parentId
        self.createdAt = Date()
        self.sortOrder = sortOrder
    }
}
