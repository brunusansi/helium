import Foundation
import AppKit

/// Service for launching Safari with system proxy configuration
/// This approach uses the native Safari browser with Helium managing the proxy
@MainActor
final class SafariLauncher: ObservableObject {
    static let shared = SafariLauncher()
    
    @Published private(set) var activeProfiles: [UUID: ProfileSession] = [:]
    @Published private(set) var originalProxyState: ProxyState?
    @Published private(set) var lastError: String?
    
    private let networkService: String
    
    private init() {
        networkService = Self.getPrimaryNetworkService() ?? "Wi-Fi"
    }
    
    /// Launch Safari with proxy configured for a profile
    func launchProfile(
        profile: Profile,
        proxy: Proxy?,
        xrayService: XrayService
    ) async throws {
        var localPort: Int?
        
        // If proxy is assigned, start Xray and configure system proxy
        if let proxy = proxy {
            if proxy.type.requiresXray {
                // Check if xray is installed
                guard await xrayService.checkInstallation() else {
                    throw SafariLauncherError.xrayNotInstalled
                }
                
                // Start Xray connection first
                let connection = try await xrayService.startConnection(profileId: profile.id, proxy: proxy)
                localPort = connection.localPort
            } else if proxy.type == .socks5 {
                // Direct SOCKS5 proxy - connect directly
                localPort = proxy.port
            }
            
            if let port = localPort {
                // Save original proxy settings before modifying
                if originalProxyState == nil {
                    originalProxyState = await captureProxyState()
                }
                
                // Configure system SOCKS proxy
                try await configureSystemProxy(host: "127.0.0.1", port: port)
            }
        }
        
        // Create session record
        let session = ProfileSession(
            profileId: profile.id,
            proxyId: proxy?.id,
            localPort: localPort,
            startedAt: Date()
        )
        activeProfiles[profile.id] = session
        
        // Launch Safari with the start URL
        launchSafari(startURL: profile.startUrl)
        
        lastError = nil
    }
    
    /// Stop a profile session and restore proxy settings
    func stopProfile(profileId: UUID, xrayService: XrayService) async {
        guard activeProfiles[profileId] != nil else { return }
        
        // Stop Xray connection if running
        xrayService.stopConnection(profileId: profileId)
        
        // Remove from active profiles
        activeProfiles.removeValue(forKey: profileId)
        
        // If no more active profiles with proxy, restore original settings
        if activeProfiles.isEmpty {
            await restoreProxyState()
        }
    }
    
    /// Stop all profiles
    func stopAllProfiles(xrayService: XrayService) async {
        for profileId in activeProfiles.keys {
            xrayService.stopConnection(profileId: profileId)
        }
        activeProfiles.removeAll()
        await restoreProxyState()
    }
    
    /// Check if a profile is currently active
    func isProfileActive(_ profileId: UUID) -> Bool {
        activeProfiles[profileId] != nil
    }
    
    // MARK: - Safari Launch
    
    private func launchSafari(startURL: String, useContainer: Bool = false, profileId: UUID? = nil) {
        let url = URL(string: startURL) ?? URL(string: "https://www.google.com")!
        
        if useContainer, let profileId = profileId {
            // Launch Safari in a new container/window with isolation
            // Using AppleScript to create a new private window
            let script = """
            tell application "Safari"
                activate
                make new document with properties {URL:"\(startURL)"}
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if error != nil {
                    // Fallback to regular open
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Launch Safari in container mode (separate window, still shares system proxy)
    func launchProfileContainer(
        profile: Profile,
        proxy: Proxy?,
        xrayService: XrayService
    ) async throws {
        var localPort: Int?
        
        // If proxy is assigned, start Xray and configure system proxy
        if let proxy = proxy {
            if proxy.type.requiresXray {
                guard await xrayService.checkInstallation() else {
                    throw SafariLauncherError.xrayNotInstalled
                }
                
                let connection = try await xrayService.startConnection(profileId: profile.id, proxy: proxy)
                localPort = connection.localPort
            } else if proxy.type == .socks5 {
                localPort = proxy.port
            }
            
            if let port = localPort {
                if originalProxyState == nil {
                    originalProxyState = await captureProxyState()
                }
                try await configureSystemProxy(host: "127.0.0.1", port: port)
            }
        }
        
        // Create session record
        let session = ProfileSession(
            profileId: profile.id,
            proxyId: proxy?.id,
            localPort: localPort,
            startedAt: Date()
        )
        activeProfiles[profile.id] = session
        
        // Launch Safari in container mode
        launchSafari(startURL: profile.startUrl, useContainer: true, profileId: profile.id)
        
        lastError = nil
    }
    
    // MARK: - System Proxy Configuration
    
    private func configureSystemProxy(host: String, port: Int) async throws {
        // Enable SOCKS proxy
        let setProxy = Process()
        setProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        setProxy.arguments = ["-setsocksfirewallproxy", networkService, host, String(port)]
        
        try setProxy.run()
        setProxy.waitUntilExit()
        
        guard setProxy.terminationStatus == 0 else {
            throw SafariLauncherError.proxyConfigFailed
        }
        
        // Turn on SOCKS proxy
        let enableProxy = Process()
        enableProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        enableProxy.arguments = ["-setsocksfirewallproxystate", networkService, "on"]
        
        try enableProxy.run()
        enableProxy.waitUntilExit()
        
        print("[SafariLauncher] SOCKS proxy enabled on \(host):\(port)")
    }
    
    private func disableSystemProxy() async {
        let disableProxy = Process()
        disableProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        disableProxy.arguments = ["-setsocksfirewallproxystate", networkService, "off"]
        
        do {
            try disableProxy.run()
            disableProxy.waitUntilExit()
            print("[SafariLauncher] SOCKS proxy disabled")
        } catch {
            print("[SafariLauncher] Failed to disable proxy: \(error)")
        }
    }
    
    private func captureProxyState() async -> ProxyState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getsocksfirewallproxy", networkService]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let enabled = output.contains("Enabled: Yes")
            var host = ""
            var port = 0
            
            for line in output.components(separatedBy: "\n") {
                if line.starts(with: "Server:") {
                    host = line.replacingOccurrences(of: "Server: ", with: "").trimmingCharacters(in: .whitespaces)
                }
                if line.starts(with: "Port:") {
                    port = Int(line.replacingOccurrences(of: "Port: ", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            
            return ProxyState(enabled: enabled, host: host, port: port)
        } catch {
            return ProxyState(enabled: false, host: "", port: 0)
        }
    }
    
    private func restoreProxyState() async {
        guard let original = originalProxyState else {
            await disableSystemProxy()
            return
        }
        
        if original.enabled && !original.host.isEmpty && original.port > 0 {
            try? await configureSystemProxy(host: original.host, port: original.port)
        } else {
            await disableSystemProxy()
        }
        
        originalProxyState = nil
    }
    
    // MARK: - Helpers
    
    private static func getPrimaryNetworkService() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("An asterisk") {
                    if trimmed.contains("Wi-Fi") || trimmed.contains("Ethernet") {
                        return trimmed
                    }
                }
            }
            
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("An asterisk") {
                    return trimmed
                }
            }
        } catch {
            // Ignore
        }
        
        return nil
    }
}

// MARK: - Supporting Types

struct ProfileSession: Identifiable {
    let id = UUID()
    let profileId: UUID
    let proxyId: UUID?
    let localPort: Int?
    let startedAt: Date
}

struct ProxyState {
    let enabled: Bool
    let host: String
    let port: Int
}

enum SafariLauncherError: LocalizedError {
    case proxyConfigFailed
    case xrayNotInstalled
    
    var errorDescription: String? {
        switch self {
        case .proxyConfigFailed:
            return "Failed to configure system proxy. You may need to grant permissions in System Settings > Privacy & Security."
        case .xrayNotInstalled:
            return "Xray-core is not installed. Please install it from Settings > Network."
        }
    }
}
