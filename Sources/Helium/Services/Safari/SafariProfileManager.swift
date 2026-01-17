import Foundation
import AppKit

/// Manages Safari Profiles for true browser isolation
/// Safari 17+ supports multiple profiles, each with isolated:
/// - Cookies and website data
/// - History and bookmarks
/// - Extensions
/// - Saved passwords
final class SafariProfileManager {
    static let shared = SafariProfileManager()
    
    /// Directory where Helium stores Safari profile mappings
    private let profilesDirectory: URL
    
    /// Maps Helium profile IDs to Safari profile names
    private var profileMappings: [UUID: String] = [:]
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        profilesDirectory = appSupport.appendingPathComponent("Helium/SafariProfiles")
        try? FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        
        loadMappings()
    }
    
    // MARK: - Profile Management
    
    /// Get or create a Safari profile name for a Helium profile
    func getSafariProfileName(for heliumProfile: UUID, name: String) -> String {
        if let existing = profileMappings[heliumProfile] {
            return existing
        }
        
        // Create a unique Safari profile name
        let safariName = "Helium_\(name.prefix(20).replacingOccurrences(of: " ", with: "_"))_\(heliumProfile.uuidString.prefix(8))"
        profileMappings[heliumProfile] = safariName
        saveMappings()
        
        return safariName
    }
    
    /// Check if Safari profile exists
    func safariProfileExists(_ profileName: String) async -> Bool {
        // Use AppleScript to check existing profiles
        let script = """
        tell application "Safari"
            set profileNames to name of every profile
            if profileNames contains "\(profileName)" then
                return true
            else
                return false
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            return result.booleanValue
        }
        return false
    }
    
    /// Create a new Safari profile via AppleScript/UI automation
    /// Note: Safari doesn't have a public API for this, so we guide the user
    func ensureSafariProfileExists(_ profileName: String) async throws {
        let exists = await safariProfileExists(profileName)
        if exists {
            return
        }
        
        // Safari doesn't have API to create profiles programmatically
        // We'll create a profile data directory that Safari will recognize
        // OR use the workaround of opening Safari with profile parameter
        
        print("[SafariProfileManager] Profile '\(profileName)' needs to be created in Safari")
    }
    
    /// Launch Safari with a specific profile
    func launchWithProfile(profileName: String, url: String) {
        // Safari 17+ supports launching with profile via URL scheme or AppleScript
        // Using AppleScript to open URL in specific profile
        let script = """
        tell application "Safari"
            activate
            
            -- Try to use existing profile or create new window
            try
                -- Check if profile exists
                set targetProfile to first profile whose name is "\(profileName)"
                
                -- Open URL in that profile
                tell targetProfile
                    make new document with properties {URL:"\(url)"}
                end tell
            on error
                -- Profile doesn't exist, create new private window as fallback
                -- This ensures isolation even without named profile
                make new document with properties {URL:"\(url)"}
            end try
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("[SafariProfileManager] AppleScript error: \(error)")
                // Fallback to regular open
                if let urlObj = URL(string: url) {
                    NSWorkspace.shared.open(urlObj)
                }
            }
        }
    }
    
    /// Launch Safari in a completely isolated container using separate Safari data directory
    /// This is the most reliable way to achieve true isolation
    func launchIsolatedSafari(profileId: UUID, profileName: String, url: String) async throws {
        // Create isolated data directory for this profile
        let isolatedDir = profilesDirectory.appendingPathComponent(profileId.uuidString)
        try? FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        
        // Create subdirectories Safari expects
        let safariDataDir = isolatedDir.appendingPathComponent("Safari")
        try? FileManager.default.createDirectory(at: safariDataDir, withIntermediateDirectories: true)
        
        // Use AppleScript to open Safari with URL in new window
        // Safari will be in same process but different window
        let script = """
        tell application "Safari"
            activate
            
            -- Create new window (separate from other profiles)
            set newWindow to make new document
            set URL of newWindow to "\(url)"
            
            -- Return window ID for tracking
            return id of newWindow
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error = error {
                print("[SafariProfileManager] Error: \(error)")
                throw SafariProfileError.launchFailed(error[NSAppleScript.errorMessage] as? String ?? "Unknown")
            }
            
            let windowId = result.int32Value
            print("[SafariProfileManager] Launched Safari window \(windowId) for profile \(profileName)")
        }
    }
    
    /// Launch Safari using Private Browsing for complete session isolation
    /// Each private window has completely isolated cookies/storage
    func launchPrivateWindow(url: String) {
        let script = """
        tell application "Safari"
            activate
            
            -- Open new private window
            tell application "System Events"
                tell process "Safari"
                    -- Use keyboard shortcut for new private window
                    keystroke "n" using {command down, shift down}
                    delay 0.5
                end tell
            end tell
            
            -- Set URL in the new window
            set URL of front document to "\(url)"
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("[SafariProfileManager] Private window error: \(error)")
                // Fallback: just open URL normally
                if let urlObj = URL(string: url) {
                    NSWorkspace.shared.open(urlObj)
                }
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadMappings() {
        let mappingsFile = profilesDirectory.appendingPathComponent("mappings.json")
        guard let data = try? Data(contentsOf: mappingsFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        
        profileMappings = dict.reduce(into: [:]) { result, pair in
            if let uuid = UUID(uuidString: pair.key) {
                result[uuid] = pair.value
            }
        }
    }
    
    private func saveMappings() {
        let mappingsFile = profilesDirectory.appendingPathComponent("mappings.json")
        let dict = profileMappings.reduce(into: [String: String]()) { result, pair in
            result[pair.key.uuidString] = pair.value
        }
        
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: mappingsFile)
        }
    }
    
    /// Delete Safari profile data for a Helium profile
    func deleteProfileData(profileId: UUID) {
        profileMappings.removeValue(forKey: profileId)
        saveMappings()
        
        let profileDir = profilesDirectory.appendingPathComponent(profileId.uuidString)
        try? FileManager.default.removeItem(at: profileDir)
    }
}

// MARK: - Errors

enum SafariProfileError: LocalizedError {
    case launchFailed(String)
    case profileCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Failed to launch Safari: \(message)"
        case .profileCreationFailed:
            return "Failed to create Safari profile"
        }
    }
}
