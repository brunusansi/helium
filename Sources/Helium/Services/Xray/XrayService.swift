import Foundation
import Combine

/// Service for managing Xray-core process and connections
@MainActor
final class XrayService: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var version: String?
    @Published private(set) var activeConnections: [UUID: XrayConnection] = [:]
    @Published private(set) var error: XrayError?
    
    private var xrayProcess: Process?
    private let configDirectory: URL
    private let binaryPath: URL
    
    private var basePort: Int = 10800
    private var portAllocations: [UUID: Int] = [:]
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        configDirectory = appSupport.appendingPathComponent("Helium/xray-configs", isDirectory: true)
        binaryPath = appSupport.appendingPathComponent("Helium/xray-core/xray")
        
        createDirectories()
    }
    
    private func createDirectories() {
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: binaryPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    
    // MARK: - Binary Management
    
    func checkInstallation() async -> Bool {
        FileManager.default.fileExists(atPath: binaryPath.path)
    }
    
    func getVersion() async throws -> String {
        guard await checkInstallation() else {
            throw XrayError.notInstalled
        }
        
        let process = Process()
        process.executableURL = binaryPath
        process.arguments = ["version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        // Parse version from output like "Xray 1.8.x (..."
        let pattern = try? NSRegularExpression(pattern: "Xray (\\d+\\.\\d+\\.\\d+)", options: [])
        if let match = pattern?.firstMatch(in: output, options: [], range: NSRange(output.startIndex..., in: output)),
           let versionRange = Range(match.range(at: 1), in: output) {
            let versionString = String(output[versionRange])
            version = versionString
            return versionString
        }
        
        return "Unknown"
    }
    
    func downloadXrayCore() async throws {
        // Determine architecture - Xray uses "macos-arm64-v8a" and "macos-64" naming
        #if arch(arm64)
        let arch = "macos-arm64"
        #else
        let arch = "macos-64"
        #endif
        
        // Get latest release from GitHub
        let releasesURL = URL(string: "https://api.github.com/repos/XTLS/Xray-core/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: releasesURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw XrayError.downloadFailed("Failed to parse releases")
        }
        
        // Find the correct asset (look for .zip file containing arch name)
        guard let asset = assets.first(where: { 
            guard let name = $0["name"] as? String else { return false }
            return name.contains(arch) && name.hasSuffix(".zip")
        }),
              let downloadURL = asset["browser_download_url"] as? String else {
            throw XrayError.downloadFailed("Asset not found for \(arch)")
        }
        
        // Download the zip
        let (zipData, _) = try await URLSession.shared.data(from: URL(string: downloadURL)!)
        
        // Save and extract
        let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent("xray.zip")
        try zipData.write(to: tempZip)
        
        // Extract using unzip command
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", tempZip.path, "-d", binaryPath.deletingLastPathComponent().path]
        
        try unzipProcess.run()
        unzipProcess.waitUntilExit()
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempZip)
        
        version = try await getVersion()
    }
    
    // MARK: - Connection Management
    
    func startConnection(profileId: UUID, proxy: Proxy) async throws -> XrayConnection {
        guard await checkInstallation() else {
            throw XrayError.notInstalled
        }
        
        // Allocate a local port for this profile
        let localPort = allocatePort(for: profileId)
        
        // Generate Xray config for this proxy
        let config = try generateConfig(proxy: proxy, localPort: localPort)
        let configPath = configDirectory.appendingPathComponent("\(profileId.uuidString).json")
        try config.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Start Xray process
        let process = Process()
        process.executableURL = binaryPath
        process.arguments = ["run", "-c", configPath.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        // Wait a moment for the process to start
        try await Task.sleep(nanoseconds: 500_000_000)
        
        guard process.isRunning else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw XrayError.startFailed(errorMessage)
        }
        
        let connection = XrayConnection(
            profileId: profileId,
            proxyId: proxy.id,
            localPort: localPort,
            process: process,
            startedAt: Date()
        )
        
        activeConnections[profileId] = connection
        isRunning = true
        
        return connection
    }
    
    func stopConnection(profileId: UUID) {
        guard let connection = activeConnections[profileId] else { return }
        
        connection.process.terminate()
        activeConnections.removeValue(forKey: profileId)
        releasePort(for: profileId)
        
        // Clean up config
        let configPath = configDirectory.appendingPathComponent("\(profileId.uuidString).json")
        try? FileManager.default.removeItem(at: configPath)
        
        if activeConnections.isEmpty {
            isRunning = false
        }
    }
    
    func stopAllConnections() {
        for profileId in activeConnections.keys {
            stopConnection(profileId: profileId)
        }
    }
    
    func getConnection(profileId: UUID) -> XrayConnection? {
        activeConnections[profileId]
    }
    
    // MARK: - Port Allocation
    
    private func allocatePort(for profileId: UUID) -> Int {
        if let existing = portAllocations[profileId] {
            return existing
        }
        
        var port = basePort
        while portAllocations.values.contains(port) {
            port += 1
        }
        
        portAllocations[profileId] = port
        return port
    }
    
    private func releasePort(for profileId: UUID) {
        portAllocations.removeValue(forKey: profileId)
    }
    
    // MARK: - Config Generation
    
    private func generateConfig(proxy: Proxy, localPort: Int) throws -> String {
        var outbound: [String: Any]
        
        switch proxy.settings {
        case .shadowsocks(let settings):
            outbound = [
                "protocol": "shadowsocks",
                "settings": [
                    "servers": [[
                        "address": proxy.host,
                        "port": proxy.port,
                        "method": settings.method,
                        "password": proxy.password ?? ""
                    ]]
                ]
            ]
            
        case .vmess(let settings):
            outbound = [
                "protocol": "vmess",
                "settings": [
                    "vnext": [[
                        "address": proxy.host,
                        "port": proxy.port,
                        "users": [[
                            "id": settings.uuid,
                            "alterId": settings.alterId,
                            "security": settings.security ?? "auto"
                        ]]
                    ]]
                ],
                "streamSettings": buildStreamSettings(network: settings.network, path: settings.path, wsHost: settings.wsHost)
            ]
            
        case .vless(let settings):
            var streamSettings = buildStreamSettings(network: settings.network, path: settings.path, wsHost: settings.wsHost)
            
            if settings.security == "reality" {
                streamSettings["security"] = "reality"
                streamSettings["realitySettings"] = [
                    "serverName": settings.sni ?? "",
                    "fingerprint": settings.fingerprint ?? "chrome",
                    "publicKey": settings.publicKey ?? "",
                    "shortId": settings.shortId ?? ""
                ]
            } else if settings.security == "tls" {
                streamSettings["security"] = "tls"
                streamSettings["tlsSettings"] = [
                    "serverName": settings.sni ?? proxy.host,
                    "fingerprint": settings.fingerprint ?? "chrome"
                ]
            }
            
            outbound = [
                "protocol": "vless",
                "settings": [
                    "vnext": [[
                        "address": proxy.host,
                        "port": proxy.port,
                        "users": [[
                            "id": settings.uuid,
                            "encryption": settings.encryption,
                            "flow": settings.flow ?? ""
                        ]]
                    ]]
                ],
                "streamSettings": streamSettings
            ]
            
        case .trojan(let settings):
            let streamSettings: [String: Any] = [
                "network": "tcp",
                "security": "tls",
                "tlsSettings": [
                    "serverName": settings.sni ?? proxy.host,
                    "fingerprint": settings.fingerprint ?? "chrome",
                    "alpn": settings.alpn ?? ["h2", "http/1.1"]
                ]
            ]
            
            outbound = [
                "protocol": "trojan",
                "settings": [
                    "servers": [[
                        "address": proxy.host,
                        "port": proxy.port,
                        "password": proxy.password ?? ""
                    ]]
                ],
                "streamSettings": streamSettings
            ]
            
        case .none:
            throw XrayError.unsupportedProtocol
        }
        
        outbound["tag"] = "proxy"
        
        let config: [String: Any] = [
            "log": [
                "loglevel": "warning"
            ],
            "inbounds": [
                [
                    "tag": "socks",
                    "port": localPort,
                    "listen": "127.0.0.1",
                    "protocol": "socks",
                    "settings": [
                        "auth": "noauth",
                        "udp": true
                    ]
                ],
                [
                    "tag": "http",
                    "port": localPort + 1,
                    "listen": "127.0.0.1",
                    "protocol": "http"
                ]
            ],
            "outbounds": [
                outbound,
                [
                    "protocol": "freedom",
                    "tag": "direct"
                ],
                [
                    "protocol": "blackhole",
                    "tag": "block"
                ]
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
    
    private func buildStreamSettings(network: String, path: String?, wsHost: String?) -> [String: Any] {
        var settings: [String: Any] = ["network": network]
        
        switch network {
        case "ws":
            var wsSettings: [String: Any] = [:]
            if let path = path { wsSettings["path"] = path }
            if let host = wsHost { wsSettings["headers"] = ["Host": host] }
            settings["wsSettings"] = wsSettings
            
        case "grpc":
            if let serviceName = path {
                settings["grpcSettings"] = ["serviceName": serviceName]
            }
            
        case "http", "h2":
            var httpSettings: [String: Any] = [:]
            if let path = path { httpSettings["path"] = path }
            if let host = wsHost { httpSettings["host"] = [host] }
            settings["httpSettings"] = httpSettings
            
        default:
            break
        }
        
        return settings
    }
}

// MARK: - Xray Connection

struct XrayConnection {
    let profileId: UUID
    let proxyId: UUID
    let localPort: Int
    let process: Process
    let startedAt: Date
    
    var socksAddress: String {
        "socks5://127.0.0.1:\(localPort)"
    }
    
    var httpAddress: String {
        "http://127.0.0.1:\(localPort + 1)"
    }
    
    var isRunning: Bool {
        process.isRunning
    }
}

// MARK: - Xray Errors

enum XrayError: LocalizedError {
    case notInstalled
    case downloadFailed(String)
    case startFailed(String)
    case unsupportedProtocol
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Xray-core is not installed"
        case .downloadFailed(let reason):
            return "Failed to download Xray-core: \(reason)"
        case .startFailed(let reason):
            return "Failed to start Xray: \(reason)"
        case .unsupportedProtocol:
            return "Unsupported proxy protocol"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        }
    }
}
