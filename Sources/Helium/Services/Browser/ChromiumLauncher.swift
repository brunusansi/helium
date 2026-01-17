import Foundation
import AppKit

/// Service for launching Chromium with per-profile proxy and data isolation
@MainActor
final class ChromiumLauncher: ObservableObject {
    static let shared = ChromiumLauncher()
    
    @Published private(set) var activeProfiles: [UUID: ChromiumSession] = [:]
    @Published private(set) var isChromiumInstalled: Bool = false
    @Published private(set) var chromiumPath: String?
    @Published private(set) var lastError: String?
    
    private let profilesDirectory: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        profilesDirectory = appSupport.appendingPathComponent("Helium/chromium-profiles", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        
        detectChromium()
    }
    
    /// Detect installed Chromium-based browsers
    func detectChromium() {
        let browsers = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi",
            "/Applications/Arc.app/Contents/MacOS/Arc"
        ]
        
        for browser in browsers {
            if FileManager.default.fileExists(atPath: browser) {
                chromiumPath = browser
                isChromiumInstalled = true
                return
            }
        }
        
        isChromiumInstalled = false
    }
    
    /// Get the name of the detected browser
    var detectedBrowserName: String {
        guard let path = chromiumPath else { return "Not installed" }
        if path.contains("Google Chrome") { return "Google Chrome" }
        if path.contains("Chromium") { return "Chromium" }
        if path.contains("Brave") { return "Brave Browser" }
        if path.contains("Microsoft Edge") { return "Microsoft Edge" }
        if path.contains("Vivaldi") { return "Vivaldi" }
        if path.contains("Arc") { return "Arc" }
        return "Unknown"
    }
    
    /// Launch Chromium with isolated profile and proxy
    func launchProfile(
        profile: Profile,
        proxy: Proxy?,
        xrayService: XrayService
    ) async throws {
        guard let browserPath = chromiumPath else {
            throw ChromiumLauncherError.chromiumNotInstalled
        }
        
        // Create profile-specific data directory
        let profileDataDir = profilesDirectory.appendingPathComponent(profile.id.uuidString)
        try? FileManager.default.createDirectory(at: profileDataDir, withIntermediateDirectories: true)
        
        var proxyArg: String?
        var localPort: Int?
        
        // If proxy is assigned, start Xray and get local port
        if let proxy = proxy {
            if proxy.type.requiresXray {
                guard await xrayService.checkInstallation() else {
                    throw ChromiumLauncherError.xrayNotInstalled
                }
                
                let connection = try await xrayService.startConnection(profileId: profile.id, proxy: proxy)
                localPort = connection.localPort
                proxyArg = "socks5://127.0.0.1:\(connection.localPort)"
            } else if proxy.type == .socks5 {
                proxyArg = "socks5://\(proxy.host):\(proxy.port)"
                localPort = proxy.port
            } else if proxy.type == .http {
                proxyArg = "http://\(proxy.host):\(proxy.port)"
                localPort = proxy.port
            }
        }
        
        // Build Chromium arguments
        var arguments = [
            "--user-data-dir=\(profileDataDir.path)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-client-side-phishing-detection",
            "--disable-default-apps",
            "--disable-hang-monitor",
            "--disable-popup-blocking",
            "--disable-prompt-on-repost",
            "--disable-sync",
            "--disable-translate",
            "--metrics-recording-only",
            "--safebrowsing-disable-auto-update",
            // Anti-detection flags
            "--disable-blink-features=AutomationControlled",
            "--disable-features=IsolateOrigins,site-per-process",
            "--disable-infobars",
            "--disable-dev-shm-usage",
            "--disable-gpu-sandbox"
        ]
        
        // Add proxy if configured
        if let proxyArg = proxyArg {
            arguments.append("--proxy-server=\(proxyArg)")
        }
        
        // Add start URL
        arguments.append(profile.startUrl)
        
        // Launch Chromium
        let process = Process()
        process.executableURL = URL(fileURLWithPath: browserPath)
        process.arguments = arguments
        
        // Don't wait for process - it runs independently
        try process.run()
        
        // Create session record
        let session = ChromiumSession(
            profileId: profile.id,
            proxyId: proxy?.id,
            localPort: localPort,
            process: process,
            dataDirectory: profileDataDir,
            startedAt: Date()
        )
        activeProfiles[profile.id] = session
        
        lastError = nil
    }
    
    /// Stop a profile session
    func stopProfile(profileId: UUID, xrayService: XrayService) {
        guard let session = activeProfiles[profileId] else { return }
        
        // Terminate Chromium process if still running
        if session.process.isRunning {
            session.process.terminate()
        }
        
        // Stop Xray connection if running
        xrayService.stopConnection(profileId: profileId)
        
        // Remove from active profiles
        activeProfiles.removeValue(forKey: profileId)
    }
    
    /// Stop all profiles
    func stopAllProfiles(xrayService: XrayService) {
        for profileId in activeProfiles.keys {
            stopProfile(profileId: profileId, xrayService: xrayService)
        }
    }
    
    /// Check if a profile is currently active
    func isProfileActive(_ profileId: UUID) -> Bool {
        guard let session = activeProfiles[profileId] else { return false }
        return session.process.isRunning
    }
    
    /// Delete profile data directory
    func deleteProfileData(profileId: UUID) {
        let profileDataDir = profilesDirectory.appendingPathComponent(profileId.uuidString)
        try? FileManager.default.removeItem(at: profileDataDir)
    }
    
    /// Get profile data size
    func getProfileDataSize(profileId: UUID) -> Int64 {
        let profileDataDir = profilesDirectory.appendingPathComponent(profileId.uuidString)
        return directorySize(at: profileDataDir)
    }
    
    private func directorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }
}

// MARK: - Supporting Types

struct ChromiumSession {
    let profileId: UUID
    let proxyId: UUID?
    let localPort: Int?
    let process: Process
    let dataDirectory: URL
    let startedAt: Date
    
    var isRunning: Bool {
        process.isRunning
    }
}

enum ChromiumLauncherError: LocalizedError {
    case chromiumNotInstalled
    case xrayNotInstalled
    case launchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .chromiumNotInstalled:
            return "No Chromium-based browser found. Please install Chrome, Chromium, Brave, Edge, or Vivaldi."
        case .xrayNotInstalled:
            return "Xray-core is not installed. Please install it from Settings > Xray-core."
        case .launchFailed(let reason):
            return "Failed to launch browser: \(reason)"
        }
    }
}
