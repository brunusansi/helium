import Foundation

/// Manages TUN interfaces and tun2socks for per-profile network isolation
/// 
/// Architecture:
/// ```
/// Profile A → tun0 (10.0.0.1) → Xray:10800 → Proxy A
/// Profile B → tun1 (10.0.1.1) → Xray:10801 → Proxy B  
/// Profile C → tun2 (10.0.2.1) → Xray:10802 → Proxy C
/// ```
///
/// Each Safari window is bound to a specific TUN interface via PAC file
@MainActor
final class TunManager: ObservableObject {
    static let shared = TunManager()
    
    @Published private(set) var activeTunnels: [UUID: TunSession] = [:]
    @Published private(set) var isTun2SocksInstalled: Bool = false
    @Published private(set) var lastError: String?
    
    private let tunDirectory: URL
    private let binaryPath: URL
    private var usedTunIndices: Set<Int> = []
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        tunDirectory = appSupport.appendingPathComponent("Helium/tun", isDirectory: true)
        binaryPath = tunDirectory.appendingPathComponent("tun2socks")
        
        try? FileManager.default.createDirectory(at: tunDirectory, withIntermediateDirectories: true)
        
        checkInstallation()
    }
    
    // MARK: - Installation
    
    func checkInstallation() {
        isTun2SocksInstalled = FileManager.default.fileExists(atPath: binaryPath.path)
    }
    
    /// Download tun2socks binary from GitHub releases
    func downloadTun2Socks() async throws {
        // tun2socks releases: https://github.com/xjasonlyu/tun2socks/releases
        #if arch(arm64)
        let arch = "darwin-arm64"
        #else
        let arch = "darwin-amd64"
        #endif
        
        let releasesURL = URL(string: "https://api.github.com/repos/xjasonlyu/tun2socks/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: releasesURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw TunError.downloadFailed("Failed to parse releases")
        }
        
        // Find the correct asset (tun2socks-darwin-arm64.zip or tun2socks-darwin-amd64.zip)
        guard let asset = assets.first(where: {
            guard let name = $0["name"] as? String else { return false }
            return name.contains(arch) && name.hasSuffix(".zip")
        }),
              let downloadURL = asset["browser_download_url"] as? String else {
            throw TunError.downloadFailed("Asset not found for \(arch)")
        }
        
        // Download the zip
        let (zipData, _) = try await URLSession.shared.data(from: URL(string: downloadURL)!)
        
        // Save and extract
        let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent("tun2socks.zip")
        try zipData.write(to: tempZip)
        
        // Extract
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", tempZip.path, "-d", tunDirectory.path]
        
        try unzipProcess.run()
        unzipProcess.waitUntilExit()
        
        // The binary might be extracted with a different name, find it
        let contents = try FileManager.default.contentsOfDirectory(at: tunDirectory, includingPropertiesForKeys: nil)
        if let extractedBinary = contents.first(where: { $0.lastPathComponent.hasPrefix("tun2socks") && !$0.lastPathComponent.hasSuffix(".zip") }) {
            // Rename to standard name
            if extractedBinary.path != binaryPath.path {
                try? FileManager.default.removeItem(at: binaryPath)
                try FileManager.default.moveItem(at: extractedBinary, to: binaryPath)
            }
        }
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempZip)
        
        checkInstallation()
    }
    
    // MARK: - TUN Interface Management
    
    /// Create a TUN interface for a profile with the given SOCKS5 proxy
    func createTunnel(profileId: UUID, socksPort: Int) async throws -> TunSession {
        guard isTun2SocksInstalled else {
            throw TunError.notInstalled
        }
        
        // Allocate TUN interface
        let tunIndex = allocateTunIndex()
        let tunDevice = "utun\(tunIndex)"
        let tunIP = "10.0.\(tunIndex).1"
        let tunGateway = "10.0.\(tunIndex).0"
        let tunSubnet = "10.0.\(tunIndex).0/24"
        
        // Start tun2socks process
        // tun2socks -device utun0 -proxy socks5://127.0.0.1:10800
        let process = Process()
        process.executableURL = binaryPath
        process.arguments = [
            "-device", tunDevice,
            "-proxy", "socks5://127.0.0.1:\(socksPort)",
            "-loglevel", "warn"
        ]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        // Wait for interface to come up
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        guard process.isRunning else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            releaseTunIndex(tunIndex)
            throw TunError.startFailed(errorMessage)
        }
        
        // Configure routing for this TUN interface
        try await configureRouting(tunDevice: tunDevice, tunIP: tunIP, tunGateway: tunGateway)
        
        let session = TunSession(
            profileId: profileId,
            tunDevice: tunDevice,
            tunIndex: tunIndex,
            tunIP: tunIP,
            tunGateway: tunGateway,
            tunSubnet: tunSubnet,
            socksPort: socksPort,
            process: process,
            startedAt: Date()
        )
        
        activeTunnels[profileId] = session
        
        return session
    }
    
    /// Stop a TUN tunnel for a profile
    func stopTunnel(profileId: UUID) async {
        guard let session = activeTunnels[profileId] else { return }
        
        // Remove routing rules
        await removeRouting(tunDevice: session.tunDevice)
        
        // Terminate tun2socks process
        if session.process.isRunning {
            session.process.terminate()
        }
        
        // Release TUN index
        releaseTunIndex(session.tunIndex)
        
        // Remove PAC file
        let pacFile = tunDirectory.appendingPathComponent("profile_\(session.profileId.uuidString).pac")
        try? FileManager.default.removeItem(at: pacFile)
        
        activeTunnels.removeValue(forKey: profileId)
    }
    
    /// Stop all tunnels
    func stopAllTunnels() async {
        for profileId in activeTunnels.keys {
            await stopTunnel(profileId: profileId)
        }
    }
    
    // MARK: - Routing Configuration
    
    private func configureRouting(tunDevice: String, tunIP: String, tunGateway: String) async throws {
        // Note: Creating TUN interfaces and routing requires elevated privileges
        // tun2socks handles this internally when run with appropriate permissions
        print("[TunManager] TUN interface \(tunDevice) starting with IP \(tunIP)")
    }
    
    private func removeRouting(tunDevice: String) async {
        print("[TunManager] TUN interface \(tunDevice) stopping")
    }
    
    // MARK: - TUN Index Allocation
    
    private func allocateTunIndex() -> Int {
        var index = 10 // Start from utun10 to avoid conflicts with system
        while usedTunIndices.contains(index) {
            index += 1
        }
        usedTunIndices.insert(index)
        return index
    }
    
    private func releaseTunIndex(_ index: Int) {
        usedTunIndices.remove(index)
    }
    
    // MARK: - PAC File Generation
    
    /// Create a PAC file that routes all traffic through the profile's SOCKS proxy
    func createPacFile(for session: TunSession) -> URL {
        let pacContent = """
        function FindProxyForURL(url, host) {
            // Route all traffic through profile's SOCKS proxy
            return "SOCKS5 127.0.0.1:\(session.socksPort); DIRECT";
        }
        """
        
        let pacFile = tunDirectory.appendingPathComponent("profile_\(session.profileId.uuidString).pac")
        try? pacContent.write(to: pacFile, atomically: true, encoding: .utf8)
        
        return pacFile
    }
    
    /// Configure system to use PAC file for auto proxy configuration
    func setSystemPacFile(_ pacFile: URL, networkService: String) async throws {
        // Set auto proxy URL
        let setAutoProxy = Process()
        setAutoProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        setAutoProxy.arguments = ["-setautoproxyurl", networkService, pacFile.absoluteString]
        
        try setAutoProxy.run()
        setAutoProxy.waitUntilExit()
        
        guard setAutoProxy.terminationStatus == 0 else {
            throw TunError.configurationFailed("Failed to set auto proxy URL")
        }
        
        // Enable auto proxy
        let enableAutoProxy = Process()
        enableAutoProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        enableAutoProxy.arguments = ["-setautoproxystate", networkService, "on"]
        
        try enableAutoProxy.run()
        enableAutoProxy.waitUntilExit()
        
        print("[TunManager] PAC file configured: \(pacFile.path)")
    }
    
    /// Disable system auto proxy
    func clearSystemPacFile(networkService: String) async {
        let disableAutoProxy = Process()
        disableAutoProxy.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        disableAutoProxy.arguments = ["-setautoproxystate", networkService, "off"]
        
        do {
            try disableAutoProxy.run()
            disableAutoProxy.waitUntilExit()
            print("[TunManager] Auto proxy disabled")
        } catch {
            print("[TunManager] Failed to disable auto proxy: \(error)")
        }
    }
}

// MARK: - TUN Session

struct TunSession: Identifiable {
    let id = UUID()
    let profileId: UUID
    let tunDevice: String
    let tunIndex: Int
    let tunIP: String
    let tunGateway: String
    let tunSubnet: String
    let socksPort: Int
    let process: Process
    let startedAt: Date
    
    var isRunning: Bool {
        process.isRunning
    }
}

// MARK: - TUN Errors

enum TunError: LocalizedError {
    case notInstalled
    case downloadFailed(String)
    case startFailed(String)
    case configurationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "tun2socks is not installed. Please install it from Settings > Network."
        case .downloadFailed(let reason):
            return "Failed to download tun2socks: \(reason)"
        case .startFailed(let reason):
            return "Failed to start TUN interface: \(reason)"
        case .configurationFailed(let reason):
            return "Failed to configure routing: \(reason)"
        }
    }
}
