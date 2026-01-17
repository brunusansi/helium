import Foundation
import Combine

/// Manages proxy configurations and connections
@MainActor
final class ProxyManager: ObservableObject {
    @Published private(set) var proxies: [Proxy] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var checkingProxies: Set<UUID> = []
    
    private let storage: ProxyStorage
    private var cancellables = Set<AnyCancellable>()
    private var testProcesses: [UUID: Process] = [:]
    
    init(storage: ProxyStorage = .shared) {
        self.storage = storage
        Task { await load() }
    }
    
    // MARK: - Load & Save
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            proxies = try await storage.loadProxies()
        } catch {
            print("Failed to load proxies: \(error)")
        }
    }
    
    func save() async {
        do {
            try await storage.saveProxies(proxies)
        } catch {
            print("Failed to save proxies: \(error)")
        }
    }
    
    // MARK: - CRUD
    
    func addProxy(_ proxy: Proxy) {
        proxies.append(proxy)
        Task { await save() }
    }
    
    func updateProxy(_ proxy: Proxy) {
        if let index = proxies.firstIndex(where: { $0.id == proxy.id }) {
            proxies[index] = proxy
            Task { await save() }
        }
    }
    
    func deleteProxy(_ id: UUID) {
        proxies.removeAll { $0.id == id }
        Task { await save() }
    }
    
    func deleteProxies(_ ids: Set<UUID>) {
        proxies.removeAll { ids.contains($0.id) }
        Task { await save() }
    }
    
    func getProxy(_ id: UUID) -> Proxy? {
        proxies.first { $0.id == id }
    }
    
    // MARK: - Import
    
    func importFromURL(_ urlString: String) throws -> Proxy {
        let proxy = try Proxy.parse(urlString)
        addProxy(proxy)
        return proxy
    }
    
    func importMultiple(_ text: String) -> (success: Int, failed: Int) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var success = 0
        var failed = 0
        
        for line in lines {
            do {
                _ = try importFromURL(line)
                success += 1
            } catch {
                failed += 1
                print("Failed to parse: \(line) - \(error)")
            }
        }
        
        return (success, failed)
    }
    
    // MARK: - Proxy Check
    
    func checkProxy(_ id: UUID) async {
        guard var proxy = getProxy(id) else { return }
        
        checkingProxies.insert(id)
        proxy.status = .checking
        updateProxy(proxy)
        
        defer {
            checkingProxies.remove(id)
        }
        
        do {
            let (latency, location) = try await performProxyCheck(proxy)
            proxy.status = .online
            proxy.lastLatency = latency
            proxy.lastCheckedAt = Date()
            if let loc = location {
                proxy.country = loc.country
                proxy.countryCode = loc.countryCode
            }
        } catch {
            proxy.status = .offline
            proxy.lastCheckedAt = Date()
        }
        
        updateProxy(proxy)
    }
    
    func checkAllProxies() async {
        await withTaskGroup(of: Void.self) { group in
            for proxy in proxies {
                group.addTask { [weak self] in
                    await self?.checkProxy(proxy.id)
                }
            }
        }
    }
    
    private func performProxyCheck(_ proxy: Proxy) async throws -> (latency: Int, location: ProxyLocation?) {
        let startTime = Date()
        
        // For Xray protocols (ss, vmess, vless, trojan), we need to start xray-core temporarily
        switch proxy.type {
        case .shadowsocks, .vmess, .vless, .trojan:
            return try await performXrayProxyCheck(proxy, startTime: startTime)
        case .http, .socks5:
            return try await performSimpleProxyCheck(proxy, startTime: startTime)
        }
    }
    
    private func performSimpleProxyCheck(_ proxy: Proxy, startTime: Date) async throws -> (latency: Int, location: ProxyLocation?) {
        var request = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
        request.timeoutInterval = 10
        
        // Configure proxy for URLSession
        let config = URLSessionConfiguration.ephemeral
        
        switch proxy.type {
        case .http:
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPProxy: proxy.host,
                kCFNetworkProxiesHTTPPort: proxy.port,
                kCFNetworkProxiesHTTPSEnable: true,
                kCFNetworkProxiesHTTPSProxy: proxy.host,
                kCFNetworkProxiesHTTPSPort: proxy.port
            ]
        case .socks5:
            config.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable: true,
                kCFNetworkProxiesSOCKSProxy: proxy.host,
                kCFNetworkProxiesSOCKSPort: proxy.port
            ]
        default:
            break
        }
        
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: request)
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Try to get location from IP
        var location: ProxyLocation?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ip = json["ip"] as? String {
            location = try? await fetchIPLocation(ip)
        }
        
        return (latency, location)
    }
    
    private func performXrayProxyCheck(_ proxy: Proxy, startTime: Date) async throws -> (latency: Int, location: ProxyLocation?) {
        // Use a unique test port
        let testPort = 19000 + Int.random(in: 0..<1000)
        
        // Check if xray-core is installed
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let xrayPath = appSupport.appendingPathComponent("Helium/xray-core/xray")
        let configDir = appSupport.appendingPathComponent("Helium/xray-configs")
        
        // Create config directory if needed
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        guard FileManager.default.fileExists(atPath: xrayPath.path) else {
            throw ProxyCheckError.xrayNotInstalled
        }
        
        // Generate minimal xray config for testing
        let config = try generateTestConfig(proxy: proxy, localPort: testPort)
        let configPath = configDir.appendingPathComponent("test-\(proxy.id.uuidString).json")
        try config.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Start xray process
        let process = Process()
        process.executableURL = xrayPath
        process.arguments = ["run", "-c", configPath.path]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        
        try process.run()
        testProcesses[proxy.id] = process
        
        defer {
            // Clean up
            process.terminate()
            testProcesses.removeValue(forKey: proxy.id)
            try? FileManager.default.removeItem(at: configPath)
        }
        
        // Wait for xray to start
        try await Task.sleep(nanoseconds: 800_000_000)
        
        guard process.isRunning else {
            throw ProxyCheckError.connectionFailed
        }
        
        // Now test through the local SOCKS proxy
        var request = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
        request.timeoutInterval = 15
        
        let config2 = URLSessionConfiguration.ephemeral
        config2.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable: true,
            kCFNetworkProxiesSOCKSProxy: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: testPort
        ]
        
        let session = URLSession(configuration: config2)
        let (data, _) = try await session.data(for: request)
        
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Get IP and location
        var location: ProxyLocation?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ip = json["ip"] as? String {
            location = try? await fetchIPLocation(ip)
        }
        
        return (latency, location)
    }
    
    private func generateTestConfig(proxy: Proxy, localPort: Int) throws -> String {
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
                ]
            ]
            
        case .vless(let settings):
            var streamSettings: [String: Any] = ["network": settings.network]
            
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
                    "serverName": settings.sni ?? proxy.host
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
            outbound = [
                "protocol": "trojan",
                "settings": [
                    "servers": [[
                        "address": proxy.host,
                        "port": proxy.port,
                        "password": proxy.password ?? ""
                    ]]
                ],
                "streamSettings": [
                    "network": "tcp",
                    "security": "tls",
                    "tlsSettings": [
                        "serverName": settings.sni ?? proxy.host
                    ]
                ]
            ]
            
        case .none:
            throw ProxyCheckError.unsupportedProtocol
        }
        
        outbound["tag"] = "proxy"
        
        let config: [String: Any] = [
            "log": ["loglevel": "none"],
            "inbounds": [[
                "port": localPort,
                "listen": "127.0.0.1",
                "protocol": "socks",
                "settings": ["udp": true]
            ]],
            "outbounds": [outbound]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
    
    private func fetchIPLocation(_ ip: String) async throws -> ProxyLocation {
        let url = URL(string: "http://ip-api.com/json/\(ip)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        return ProxyLocation(
            ip: ip,
            country: json["country"] as? String ?? "Unknown",
            countryCode: json["countryCode"] as? String ?? "XX",
            city: json["city"] as? String,
            timezone: json["timezone"] as? String,
            lat: json["lat"] as? Double,
            lon: json["lon"] as? Double
        )
    }
    
    // MARK: - Search
    
    func searchProxies(_ query: String) -> [Proxy] {
        guard !query.isEmpty else { return proxies }
        let lowercased = query.lowercased()
        return proxies.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.host.lowercased().contains(lowercased) ||
            ($0.country?.lowercased().contains(lowercased) ?? false)
        }
    }
}

// MARK: - Proxy Location

struct ProxyLocation: Codable {
    let ip: String
    let country: String
    let countryCode: String
    let city: String?
    let timezone: String?
    let lat: Double?
    let lon: Double?
}

// MARK: - Proxy Check Error

enum ProxyCheckError: LocalizedError {
    case xrayNotInstalled
    case connectionFailed
    case unsupportedProtocol
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .xrayNotInstalled:
            return "Xray-core is not installed. Please install it from Settings."
        case .connectionFailed:
            return "Failed to connect to proxy"
        case .unsupportedProtocol:
            return "Unsupported proxy protocol"
        case .timeout:
            return "Connection timed out"
        }
    }
}

// MARK: - Proxy Storage

actor ProxyStorage {
    static let shared = ProxyStorage()
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Helium", isDirectory: true)
    }
    
    private var proxiesFile: URL {
        dataDirectory.appendingPathComponent("proxies.json")
    }
    
    init() {
        encoder.outputFormatting = .prettyPrinted
        // Create data directory synchronously on init
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Helium", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    private func createDataDirectory() {
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }
    
    func loadProxies() throws -> [Proxy] {
        guard FileManager.default.fileExists(atPath: proxiesFile.path) else { return [] }
        let data = try Data(contentsOf: proxiesFile)
        return try decoder.decode([Proxy].self, from: data)
    }
    
    func saveProxies(_ proxies: [Proxy]) throws {
        let data = try encoder.encode(proxies)
        try data.write(to: proxiesFile, options: .atomic)
    }
}
