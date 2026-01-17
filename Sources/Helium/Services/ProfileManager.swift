import Foundation
import Combine

/// Manages browser profiles - CRUD operations and persistence
@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var isLoading: Bool = false
    
    private let storage: ProfileStorage
    private var cancellables = Set<AnyCancellable>()
    
    init(storage: ProfileStorage = .shared) {
        self.storage = storage
        Task { await load() }
    }
    
    // MARK: - Load & Save
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            profiles = try await storage.loadProfiles()
            folders = try await storage.loadFolders()
            tags = try await storage.loadTags()
        } catch {
            print("Failed to load data: \(error)")
        }
    }
    
    func save() async {
        do {
            try await storage.saveProfiles(profiles)
            try await storage.saveFolders(folders)
            try await storage.saveTags(tags)
        } catch {
            print("Failed to save data: \(error)")
        }
    }
    
    // MARK: - Profile CRUD
    
    func createProfile(name: String, folderId: UUID? = nil) -> Profile {
        let profile = Profile(name: name, folderId: folderId)
        profiles.append(profile)
        Task { await save() }
        return profile
    }
    
    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            Task { await save() }
        }
    }
    
    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        // Also delete profile data directory
        storage.deleteProfileData(id)
        Task { await save() }
    }
    
    func deleteProfiles(_ ids: Set<UUID>) {
        for id in ids {
            deleteProfile(id)
        }
    }
    
    func duplicateProfile(_ id: UUID) -> Profile? {
        guard let original = profiles.first(where: { $0.id == id }) else { return nil }
        
        var duplicate = original
        duplicate = Profile(
            name: "\(original.name) (Copy)",
            notes: original.notes,
            folderId: original.folderId,
            tagIds: original.tagIds,
            color: original.color,
            proxyId: original.proxyId,
            fingerprint: .random(), // Generate new fingerprint
            startUrl: original.startUrl,
            extensions: original.extensions
        )
        
        profiles.append(duplicate)
        Task { await save() }
        return duplicate
    }
    
    func launchProfile(_ id: UUID) {
        guard var profile = profiles.first(where: { $0.id == id }) else { return }
        profile.status = .running
        profile.lastUsedAt = Date()
        profile.launchCount += 1
        updateProfile(profile)
    }
    
    func stopProfile(_ id: UUID) {
        guard var profile = profiles.first(where: { $0.id == id }) else { return }
        profile.status = .ready
        updateProfile(profile)
    }
    
    // MARK: - Folder CRUD
    
    func createFolder(name: String, parentId: UUID? = nil) -> Folder {
        let maxOrder = folders.filter { $0.parentId == parentId }.map(\.sortOrder).max() ?? -1
        let folder = Folder(name: name, parentId: parentId, sortOrder: maxOrder + 1)
        folders.append(folder)
        Task { await save() }
        return folder
    }
    
    func updateFolder(_ folder: Folder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            Task { await save() }
        }
    }
    
    func deleteFolder(_ id: UUID) {
        // Move profiles in this folder to root
        for i in profiles.indices where profiles[i].folderId == id {
            profiles[i].folderId = nil
        }
        folders.removeAll { $0.id == id }
        Task { await save() }
    }
    
    func profilesInFolder(_ folderId: UUID?) -> [Profile] {
        profiles.filter { $0.folderId == folderId }
    }
    
    // MARK: - Tag CRUD
    
    func createTag(name: String, color: TagColor = .blue) -> Tag {
        let tag = Tag(name: name, color: color)
        tags.append(tag)
        Task { await save() }
        return tag
    }
    
    func updateTag(_ tag: Tag) {
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[index] = tag
            Task { await save() }
        }
    }
    
    func deleteTag(_ id: UUID) {
        // Remove tag from all profiles
        for i in profiles.indices {
            profiles[i].tagIds.remove(id)
        }
        tags.removeAll { $0.id == id }
        Task { await save() }
    }
    
    func profilesWithTag(_ tagId: UUID) -> [Profile] {
        profiles.filter { $0.tagIds.contains(tagId) }
    }
    
    // MARK: - Search & Filter
    
    func searchProfiles(_ query: String) -> [Profile] {
        guard !query.isEmpty else { return profiles }
        let lowercased = query.lowercased()
        return profiles.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.notes.lowercased().contains(lowercased)
        }
    }
    
    func getProfile(_ id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }
    
    func getFolder(_ id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }
    
    func getTag(_ id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }
}

// MARK: - Profile Storage

actor ProfileStorage {
    static let shared = ProfileStorage()
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Helium", isDirectory: true)
    }
    
    private var profilesFile: URL {
        dataDirectory.appendingPathComponent("profiles.json")
    }
    
    private var foldersFile: URL {
        dataDirectory.appendingPathComponent("folders.json")
    }
    
    private var tagsFile: URL {
        dataDirectory.appendingPathComponent("tags.json")
    }
    
    init() {
        encoder.outputFormatting = .prettyPrinted
        createDataDirectory()
    }
    
    private func createDataDirectory() {
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }
    
    func loadProfiles() throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: profilesFile.path) else { return [] }
        let data = try Data(contentsOf: profilesFile)
        return try decoder.decode([Profile].self, from: data)
    }
    
    func saveProfiles(_ profiles: [Profile]) throws {
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFile, options: .atomic)
    }
    
    func loadFolders() throws -> [Folder] {
        guard FileManager.default.fileExists(atPath: foldersFile.path) else { return [] }
        let data = try Data(contentsOf: foldersFile)
        return try decoder.decode([Folder].self, from: data)
    }
    
    func saveFolders(_ folders: [Folder]) throws {
        let data = try encoder.encode(folders)
        try data.write(to: foldersFile, options: .atomic)
    }
    
    func loadTags() throws -> [Tag] {
        guard FileManager.default.fileExists(atPath: tagsFile.path) else { return [] }
        let data = try Data(contentsOf: tagsFile)
        return try decoder.decode([Tag].self, from: data)
    }
    
    func saveTags(_ tags: [Tag]) throws {
        let data = try encoder.encode(tags)
        try data.write(to: tagsFile, options: .atomic)
    }
    
    nonisolated func deleteProfileData(_ profileId: UUID) {
        let profileDir = dataDirectory.appendingPathComponent("Profiles/\(profileId.uuidString)")
        try? FileManager.default.removeItem(at: profileDir)
    }
    
    func profileDataDirectory(_ profileId: UUID) -> URL {
        let dir = dataDirectory.appendingPathComponent("Profiles/\(profileId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
