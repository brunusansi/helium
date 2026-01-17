import Foundation
import SystemConfiguration

/// Manages system-level proxy settings for WebKit traffic routing
/// Uses macOS networksetup command to configure SOCKS proxy
@MainActor
final class SystemProxyManager: ObservableObject {
    static let shared = SystemProxyManager()
    
    @Published private(set) var isProxyActive: Bool = false
    @Published private(set) var activePort: Int?
    @Published private(set) var activeProfileId: UUID?
    
    private var originalProxySettings: [String: Any]?
    private let networkService: String
    
    private init() {
        // Get primary network service name
        networkService = Self.getPrimaryNetworkService() ?? "Wi-Fi"
    }
    
    /// Configure system SOCKS proxy for the active profile
    func enableProxy(port: Int, profileId: UUID) async throws {
        // Store original settings first (for restoration later)
        originalProxySettings = await getCurrentProxySettings()
        
        // Enable SOCKS proxy using networksetup
        let enableSOCKS = Process()
        enableSOCKS.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        enableSOCKS.arguments = ["-setsocksfirewallproxy", networkService, "127.0.0.1", String(port)]
        
        try enableSOCKS.run()
        enableSOCKS.waitUntilExit()
        
        guard enableSOCKS.terminationStatus == 0 else {
            throw ProxySystemError.configurationFailed
        }
        
        // Turn on SOCKS proxy
        let turnOnSOCKS = Process()
        turnOnSOCKS.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        turnOnSOCKS.arguments = ["-setsocksfirewallproxystate", networkService, "on"]
        
        try turnOnSOCKS.run()
        turnOnSOCKS.waitUntilExit()
        
        isProxyActive = true
        activePort = port
        activeProfileId = profileId
        
        print("[SystemProxy] Enabled SOCKS proxy on port \(port)")
    }
    
    /// Disable system SOCKS proxy
    func disableProxy() async {
        let turnOffSOCKS = Process()
        turnOffSOCKS.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        turnOffSOCKS.arguments = ["-setsocksfirewallproxystate", networkService, "off"]
        
        do {
            try turnOffSOCKS.run()
            turnOffSOCKS.waitUntilExit()
        } catch {
            print("[SystemProxy] Failed to disable: \(error)")
        }
        
        isProxyActive = false
        activePort = nil
        activeProfileId = nil
        
        print("[SystemProxy] Disabled SOCKS proxy")
    }
    
    /// Check if proxy is working by fetching IP through it
    func verifyProxy(port: Int) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable: true,
            kCFNetworkProxiesSOCKSProxy: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: port
        ] as [AnyHashable: Any]
        config.timeoutIntervalForRequest = 10
        
        let session = URLSession(configuration: config)
        let url = URL(string: "https://api.ipify.org?format=json")!
        
        let (data, _) = try await session.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String else {
            throw ProxySystemError.verificationFailed
        }
        
        return ip
    }
    
    // MARK: - Private Helpers
    
    private func getCurrentProxySettings() async -> [String: Any] {
        // Get current SOCKS proxy settings
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
            
            // Parse output
            var settings: [String: Any] = [:]
            for line in output.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: ": ")
                if parts.count == 2 {
                    settings[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return settings
        } catch {
            return [:]
        }
    }
    
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
            
            // Find first non-asterisk service (Wi-Fi or Ethernet typically)
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("An asterisk") {
                    if trimmed.contains("Wi-Fi") || trimmed.contains("Ethernet") {
                        return trimmed
                    }
                }
            }
            
            // Return first valid service
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

// MARK: - Errors

enum ProxySystemError: LocalizedError {
    case configurationFailed
    case verificationFailed
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .configurationFailed:
            return "Failed to configure system proxy"
        case .verificationFailed:
            return "Failed to verify proxy connection"
        case .notAvailable:
            return "System proxy configuration not available"
        }
    }
}
