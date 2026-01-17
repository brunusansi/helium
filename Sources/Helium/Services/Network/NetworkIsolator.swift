import Foundation
import AppKit

/// High-level service that orchestrates network isolation for Safari profiles
/// 
/// This is the main entry point for launching profiles with full network isolation:
/// 1. Starts Xray-core to convert proxy protocol → SOCKS5
/// 2. Optionally creates TUN interface for per-profile isolation
/// 3. Syncs timezone with proxy location
/// 4. Configures system proxy or PAC file
/// 5. Launches Safari with the configured network
@MainActor
final class NetworkIsolator: ObservableObject {
    static let shared = NetworkIsolator()
    
    @Published private(set) var activeProfiles: [UUID: IsolatedSession] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var webRTCProtected: Bool = false
    
    private let xrayService: XrayService
    private let tunManager: TunManager
    private let timezoneManager: TimezoneManager
    private let networkService: String
    private var originalProxyState: ProxyConfiguration?
    
    private init() {
        xrayService = XrayService()
        tunManager = TunManager.shared
        timezoneManager = TimezoneManager.shared
        networkService = Self.getPrimaryNetworkService() ?? "Wi-Fi"
    }
    
    /// Get XrayService for external access
    var xray: XrayService { xrayService }
    
    /// Get TunManager for external access
    var tun: TunManager { tunManager }
    
    /// Get TimezoneManager for external access
    var timezone: TimezoneManager { timezoneManager }
    
    // MARK: - Profile Launch
    
    /// Launch a Safari profile with network isolation
    /// - Parameters:
    ///   - profile: The profile to launch
    ///   - proxy: Optional proxy configuration
    ///   - proxyLocation: Proxy location info for timezone sync
    ///   - isolationMode: Network isolation mode
    func launchProfile(
        profile: Profile,
        proxy: Proxy?,
        proxyLocation: ProxyLocation? = nil,
        isolationMode: NetworkIsolationMode = .systemProxy
    ) async throws {
        // Step 0: Sync timezone with proxy location if available
        if let location = proxyLocation, let timezone = location.timezone {
            do {
                try await timezoneManager.syncWithProxy(timezone: timezone)
            } catch {
                print("[NetworkIsolator] Timezone sync failed (non-fatal): \(error)")
            }
        }
        
        // Step 0.5: Update WebRTC protection status
        webRTCProtected = (isolationMode == .perProfileTun && tunManager.isTun2SocksInstalled)
        
        // Step 1: Start Xray if we have a proxy that requires it
        var localPort: Int?
        
        if let proxy = proxy {
            if proxy.type.requiresXray {
                guard await xrayService.checkInstallation() else {
                    throw NetworkIsolatorError.xrayNotInstalled
                }
                
                let connection = try await xrayService.startConnection(profileId: profile.id, proxy: proxy)
                localPort = connection.localPort
            } else if proxy.type == .socks5 {
                // Direct SOCKS5 - use the proxy port directly
                localPort = proxy.port
            } else if proxy.type == .http {
                // HTTP proxy - we need to use system HTTP proxy instead of SOCKS
                try await configureHttpProxy(host: proxy.host, port: proxy.port)
                let session = IsolatedSession(
                    profileId: profile.id,
                    proxyId: proxy.id,
                    localPort: nil,
                    isolationMode: isolationMode,
                    tunSession: nil,
                    startedAt: Date(),
                    timezoneApplied: proxyLocation?.timezone
                )
                activeProfiles[profile.id] = session
                launchSafari(startURL: profile.startUrl)
                return
            }
        }
        
        // Step 2: Configure network based on isolation mode
        var tunSession: TunSession?
        
        switch isolationMode {
        case .systemProxy:
            // Simple mode: configure system SOCKS proxy
            if let port = localPort {
                try await saveAndConfigureSystemProxy(host: "127.0.0.1", port: port)
            }
            
        case .perProfileTun:
            // Advanced mode: create TUN interface per profile
            guard let port = localPort else {
                throw NetworkIsolatorError.proxyRequired
            }
            
            guard tunManager.isTun2SocksInstalled else {
                throw NetworkIsolatorError.tun2socksNotInstalled
            }
            
            // Create TUN interface
            tunSession = try await tunManager.createTunnel(profileId: profile.id, socksPort: port)
            
            // Create and set PAC file for this profile
            let pacFile = tunManager.createPacFile(for: tunSession!)
            try await tunManager.setSystemPacFile(pacFile, networkService: networkService)
            
        case .pacFile:
            // PAC file mode: create PAC that routes to SOCKS
            if let port = localPort {
                let pacFile = createPacFile(socksPort: port, profileId: profile.id)
                try await setAutoPacProxy(pacFile: pacFile)
            }
        }
        
        // Step 3: Create session record
        let session = IsolatedSession(
            profileId: profile.id,
            proxyId: proxy?.id,
            localPort: localPort,
            isolationMode: isolationMode,
            tunSession: tunSession,
            startedAt: Date(),
            timezoneApplied: proxyLocation?.timezone
        )
        activeProfiles[profile.id] = session
        
        // Step 4: Launch Safari
        launchSafari(startURL: profile.startUrl)
        
        // Step 5: Warn about WebRTC if not using TUN
        if !webRTCProtected && proxy != nil {
            print("[NetworkIsolator] ⚠️ WebRTC not protected - consider using TUN mode")
        }
        
        lastError = nil
    }
    
    /// Stop a profile and clean up network configuration
    func stopProfile(profileId: UUID) async {
        guard let session = activeProfiles[profileId] else { return }
        
        // Restore timezone if this was the last profile with timezone override
        let profilesWithTimezone = activeProfiles.values.filter { $0.timezoneApplied != nil }
        if profilesWithTimezone.count == 1 && session.timezoneApplied != nil {
            await timezoneManager.restore()
        }
        
        // Stop TUN if used
        if session.tunSession != nil {
            await tunManager.stopTunnel(profileId: profileId)
        }
        
        // Stop Xray connection
        xrayService.stopConnection(profileId: profileId)
        
        // Remove from active profiles
        activeProfiles.removeValue(forKey: profileId)
        
        // If no more active profiles, restore original network settings
        if activeProfiles.isEmpty {
            await restoreOriginalProxy()
        }
    }
    
    /// Stop all profiles
    func stopAllProfiles() async {
        for profileId in activeProfiles.keys {
            await stopProfile(profileId: profileId)
        }
    }
    
    /// Check if a profile is currently active
    func isProfileActive(_ profileId: UUID) -> Bool {
        activeProfiles[profileId] != nil
    }
    
    // MARK: - Safari Launch
    
    private func launchSafari(startURL: String) {
        let url = URL(string: startURL) ?? URL(string: "https://www.google.com")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - System Proxy Configuration
    
    private func saveAndConfigureSystemProxy(host: String, port: Int) async throws {
        // Save original proxy state if not already saved
        if originalProxyState == nil {
            originalProxyState = await captureProxyState()
        }
        
        // Configure SOCKS proxy
        let setProxy = Process()
        setProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        setProxy.arguments = ["-setsocksfirewallproxy", networkService, host, String(port)]
        
        try setProxy.run()
        setProxy.waitUntilExit()
        
        guard setProxy.terminationStatus == 0 else {
            throw NetworkIsolatorError.proxyConfigFailed
        }
        
        // Enable SOCKS proxy
        let enableProxy = Process()
        enableProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        enableProxy.arguments = ["-setsocksfirewallproxystate", networkService, "on"]
        
        try enableProxy.run()
        enableProxy.waitUntilExit()
        
        print("[NetworkIsolator] SOCKS proxy enabled: \(host):\(port)")
    }
    
    private func configureHttpProxy(host: String, port: Int) async throws {
        if originalProxyState == nil {
            originalProxyState = await captureProxyState()
        }
        
        let setProxy = Process()
        setProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        setProxy.arguments = ["-setwebproxy", networkService, host, String(port)]
        
        try setProxy.run()
        setProxy.waitUntilExit()
        
        let enableProxy = Process()
        enableProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        enableProxy.arguments = ["-setwebproxystate", networkService, "on"]
        
        try enableProxy.run()
        enableProxy.waitUntilExit()
        
        print("[NetworkIsolator] HTTP proxy enabled: \(host):\(port)")
    }
    
    private func restoreOriginalProxy() async {
        guard let original = originalProxyState else {
            // Just disable all proxies
            await disableAllProxies()
            return
        }
        
        if original.socksEnabled {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = ["-setsocksfirewallproxy", networkService, original.socksHost, String(original.socksPort)]
            try? process.run()
            process.waitUntilExit()
            
            let enable = Process()
            enable.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            enable.arguments = ["-setsocksfirewallproxystate", networkService, "on"]
            try? enable.run()
            enable.waitUntilExit()
        } else {
            let disable = Process()
            disable.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            disable.arguments = ["-setsocksfirewallproxystate", networkService, "off"]
            try? disable.run()
            disable.waitUntilExit()
        }
        
        if original.httpEnabled {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = ["-setwebproxy", networkService, original.httpHost, String(original.httpPort)]
            try? process.run()
            process.waitUntilExit()
            
            let enable = Process()
            enable.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            enable.arguments = ["-setwebproxystate", networkService, "on"]
            try? enable.run()
            enable.waitUntilExit()
        } else {
            let disable = Process()
            disable.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            disable.arguments = ["-setwebproxystate", networkService, "off"]
            try? disable.run()
            disable.waitUntilExit()
        }
        
        if original.autoproxyEnabled {
            let enable = Process()
            enable.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            enable.arguments = ["-setautoproxystate", networkService, "on"]
            try? enable.run()
            enable.waitUntilExit()
        } else {
            let disable = Process()
            disable.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            disable.arguments = ["-setautoproxystate", networkService, "off"]
            try? disable.run()
            disable.waitUntilExit()
        }
        
        originalProxyState = nil
        print("[NetworkIsolator] Original proxy settings restored")
    }
    
    private func disableAllProxies() async {
        let proxies = ["setsocksfirewallproxystate", "setwebproxystate", "setautoproxystate"]
        
        for proxyType in proxies {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = ["-\(proxyType)", networkService, "off"]
            try? process.run()
            process.waitUntilExit()
        }
        
        print("[NetworkIsolator] All proxies disabled")
    }
    
    private func captureProxyState() async -> ProxyConfiguration {
        var config = ProxyConfiguration()
        
        // Get SOCKS proxy state
        let socksProcess = Process()
        socksProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        socksProcess.arguments = ["-getsocksfirewallproxy", networkService]
        let socksPipe = Pipe()
        socksProcess.standardOutput = socksPipe
        try? socksProcess.run()
        socksProcess.waitUntilExit()
        let socksOutput = String(data: socksPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        config.socksEnabled = socksOutput.contains("Enabled: Yes")
        if let serverMatch = socksOutput.range(of: "Server: (.+)", options: .regularExpression) {
            config.socksHost = String(socksOutput[serverMatch]).replacingOccurrences(of: "Server: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let portMatch = socksOutput.range(of: "Port: (\\d+)", options: .regularExpression) {
            config.socksPort = Int(String(socksOutput[portMatch]).replacingOccurrences(of: "Port: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        
        // Get HTTP proxy state
        let httpProcess = Process()
        httpProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        httpProcess.arguments = ["-getwebproxy", networkService]
        let httpPipe = Pipe()
        httpProcess.standardOutput = httpPipe
        try? httpProcess.run()
        httpProcess.waitUntilExit()
        let httpOutput = String(data: httpPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        config.httpEnabled = httpOutput.contains("Enabled: Yes")
        
        // Get auto proxy state
        let autoProcess = Process()
        autoProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        autoProcess.arguments = ["-getautoproxyurl", networkService]
        let autoPipe = Pipe()
        autoProcess.standardOutput = autoPipe
        try? autoProcess.run()
        autoProcess.waitUntilExit()
        let autoOutput = String(data: autoPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        config.autoproxyEnabled = autoOutput.contains("Enabled: Yes")
        
        return config
    }
    
    // MARK: - PAC File
    
    private func createPacFile(socksPort: Int, profileId: UUID) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let pacDir = appSupport.appendingPathComponent("Helium/pac", isDirectory: true)
        try? FileManager.default.createDirectory(at: pacDir, withIntermediateDirectories: true)
        
        let pacContent = """
        function FindProxyForURL(url, host) {
            return "SOCKS5 127.0.0.1:\(socksPort); DIRECT";
        }
        """
        
        let pacFile = pacDir.appendingPathComponent("\(profileId.uuidString).pac")
        try? pacContent.write(to: pacFile, atomically: true, encoding: .utf8)
        
        return pacFile
    }
    
    private func setAutoPacProxy(pacFile: URL) async throws {
        if originalProxyState == nil {
            originalProxyState = await captureProxyState()
        }
        
        let setProxy = Process()
        setProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        setProxy.arguments = ["-setautoproxyurl", networkService, "file://\(pacFile.path)"]
        
        try setProxy.run()
        setProxy.waitUntilExit()
        
        let enableProxy = Process()
        enableProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        enableProxy.arguments = ["-setautoproxystate", networkService, "on"]
        
        try enableProxy.run()
        enableProxy.waitUntilExit()
        
        print("[NetworkIsolator] PAC file proxy enabled: \(pacFile.path)")
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

/// Network isolation mode for profiles
enum NetworkIsolationMode: String, Codable, CaseIterable, Identifiable {
    case systemProxy = "system_proxy"
    case pacFile = "pac_file"
    case perProfileTun = "per_profile_tun"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .systemProxy:
            return "System Proxy (Simple)"
        case .pacFile:
            return "PAC File"
        case .perProfileTun:
            return "TUN Interface (Advanced)"
        }
    }
    
    var description: String {
        switch self {
        case .systemProxy:
            return "Uses macOS system proxy. Fast and simple, but all profiles share the same proxy."
        case .pacFile:
            return "Uses a PAC file for proxy auto-configuration. Good balance of flexibility and simplicity."
        case .perProfileTun:
            return "Creates a virtual network interface per profile. Full isolation, each profile has its own proxy. Requires tun2socks."
        }
    }
    
    var requiresTun2Socks: Bool {
        self == .perProfileTun
    }
}

/// Session for an isolated profile
struct IsolatedSession: Identifiable {
    let id = UUID()
    let profileId: UUID
    let proxyId: UUID?
    let localPort: Int?
    let isolationMode: NetworkIsolationMode
    let tunSession: TunSession?
    let startedAt: Date
    let timezoneApplied: String? // Timezone that was synced with proxy
    
    /// Whether WebRTC is protected (TUN mode active)
    var isWebRTCProtected: Bool {
        isolationMode == .perProfileTun && tunSession != nil
    }
}

/// Captured proxy configuration for restoration
struct ProxyConfiguration {
    var socksEnabled: Bool = false
    var socksHost: String = ""
    var socksPort: Int = 0
    var httpEnabled: Bool = false
    var httpHost: String = ""
    var httpPort: Int = 0
    var autoproxyEnabled: Bool = false
    var autoproxyUrl: String = ""
}

// MARK: - Errors

enum NetworkIsolatorError: LocalizedError {
    case xrayNotInstalled
    case tun2socksNotInstalled
    case proxyRequired
    case proxyConfigFailed
    case tunCreationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .xrayNotInstalled:
            return "Xray-core is not installed. Install it from Settings > Xray-core."
        case .tun2socksNotInstalled:
            return "tun2socks is not installed. Install it from Settings > Network to use per-profile isolation."
        case .proxyRequired:
            return "Per-profile TUN isolation requires a proxy to be configured."
        case .proxyConfigFailed:
            return "Failed to configure system proxy. You may need to grant permissions in System Settings."
        case .tunCreationFailed(let reason):
            return "Failed to create TUN interface: \(reason)"
        }
    }
}
