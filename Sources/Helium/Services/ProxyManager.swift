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
        
        // For Xray protocols, we would use the XrayService to test
        // For simple protocols, use URLSession with proxy
        
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
            // For Xray protocols, the XrayService handles the connection
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
        createDataDirectory()
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
