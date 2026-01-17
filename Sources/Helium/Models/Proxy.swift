import Foundation

/// Proxy configuration supporting multiple protocols
struct Proxy: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: ProxyType
    var host: String
    var port: Int
    var username: String?
    var password: String?
    
    // Protocol-specific settings
    var settings: ProxySettings
    
    // Metadata
    var createdAt: Date
    var lastCheckedAt: Date?
    var lastLatency: Int? // in milliseconds
    var status: ProxyStatus
    var country: String?
    var countryCode: String?
    
    // Tags for organization
    var tagIds: Set<UUID>
    
    init(
        id: UUID = UUID(),
        name: String,
        type: ProxyType,
        host: String,
        port: Int,
        username: String? = nil,
        password: String? = nil,
        settings: ProxySettings = .none,
        tagIds: Set<UUID> = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.settings = settings
        self.createdAt = Date()
        self.lastCheckedAt = nil
        self.lastLatency = nil
        self.status = .unknown
        self.country = nil
        self.countryCode = nil
        self.tagIds = tagIds
    }
    
    /// Parse a proxy URL string into a Proxy object
    static func parse(_ urlString: String) throws -> Proxy {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("ss://") {
            return try parseShadowsocks(trimmed)
        } else if trimmed.hasPrefix("vmess://") {
            return try parseVMess(trimmed)
        } else if trimmed.hasPrefix("vless://") {
            return try parseVLess(trimmed)
        } else if trimmed.hasPrefix("trojan://") {
            return try parseTrojan(trimmed)
        } else if trimmed.hasPrefix("socks5://") || trimmed.hasPrefix("socks://") {
            return try parseSocks5(trimmed)
        } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return try parseHTTP(trimmed)
        } else {
            throw ProxyParseError.unsupportedProtocol
        }
    }
    
    // MARK: - Shadowsocks Parser
    
    private static func parseShadowsocks(_ urlString: String) throws -> Proxy {
        // Format: ss://BASE64(method:password)@host:port#name
        // or: ss://BASE64(method:password@host:port)#name
        
        var workString = String(urlString.dropFirst(5)) // Remove "ss://"
        var name = "Shadowsocks"
        
        // Extract name from fragment
        if let hashIndex = workString.firstIndex(of: "#") {
            name = String(workString[workString.index(after: hashIndex)...])
                .removingPercentEncoding ?? name
            workString = String(workString[..<hashIndex])
        }
        
        var method: String
        var password: String
        var host: String
        var port: Int
        
        if let atIndex = workString.firstIndex(of: "@") {
            // Format: BASE64(method:password)@host:port
            let userInfo = String(workString[..<atIndex])
            let serverPart = String(workString[workString.index(after: atIndex)...])
            
            guard let decoded = Data(base64Encoded: userInfo),
                  let userInfoString = String(data: decoded, encoding: .utf8) else {
                throw ProxyParseError.invalidBase64
            }
            
            let parts = userInfoString.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                throw ProxyParseError.invalidFormat
            }
            
            method = String(parts[0])
            password = String(parts[1])
            
            let serverParts = serverPart.split(separator: ":")
            guard serverParts.count == 2,
                  let portNum = Int(serverParts[1]) else {
                throw ProxyParseError.invalidFormat
            }
            
            host = String(serverParts[0])
            port = portNum
        } else {
            // Format: BASE64(method:password@host:port)
            guard let decoded = Data(base64Encoded: workString),
                  let fullString = String(data: decoded, encoding: .utf8) else {
                throw ProxyParseError.invalidBase64
            }
            
            guard let atIndex = fullString.firstIndex(of: "@") else {
                throw ProxyParseError.invalidFormat
            }
            
            let userPart = String(fullString[..<atIndex])
            let serverPart = String(fullString[fullString.index(after: atIndex)...])
            
            let userParts = userPart.split(separator: ":", maxSplits: 1)
            guard userParts.count == 2 else {
                throw ProxyParseError.invalidFormat
            }
            
            method = String(userParts[0])
            password = String(userParts[1])
            
            let serverParts = serverPart.split(separator: ":")
            guard serverParts.count == 2,
                  let portNum = Int(serverParts[1]) else {
                throw ProxyParseError.invalidFormat
            }
            
            host = String(serverParts[0])
            port = portNum
        }
        
        return Proxy(
            name: name,
            type: .shadowsocks,
            host: host,
            port: port,
            password: password,
            settings: .shadowsocks(ShadowsocksSettings(method: method))
        )
    }
    
    // MARK: - VMess Parser
    
    private static func parseVMess(_ urlString: String) throws -> Proxy {
        let base64Part = String(urlString.dropFirst(8)) // Remove "vmess://"
        
        guard let data = Data(base64Encoded: base64Part),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyParseError.invalidBase64
        }
        
        guard let host = json["add"] as? String,
              let portString = json["port"],
              let port = portString as? Int ?? Int("\(portString)"),
              let uuid = json["id"] as? String else {
            throw ProxyParseError.invalidFormat
        }
        
        let name = (json["ps"] as? String) ?? "VMess"
        let alterId = (json["aid"] as? Int) ?? Int("\(json["aid"] ?? "0")") ?? 0
        let network = (json["net"] as? String) ?? "tcp"
        let security = (json["tls"] as? String) ?? ""
        let path = (json["path"] as? String) ?? ""
        let host2 = (json["host"] as? String) ?? ""
        
        return Proxy(
            name: name,
            type: .vmess,
            host: host,
            port: port,
            settings: .vmess(VMessSettings(
                uuid: uuid,
                alterId: alterId,
                security: security.isEmpty ? nil : security,
                network: network,
                path: path.isEmpty ? nil : path,
                wsHost: host2.isEmpty ? nil : host2
            ))
        )
    }
    
    // MARK: - VLESS Parser
    
    private static func parseVLess(_ urlString: String) throws -> Proxy {
        guard let url = URL(string: urlString),
              let host = url.host,
              let port = url.port else {
            throw ProxyParseError.invalidFormat
        }
        
        let uuid = url.user ?? ""
        let name = url.fragment?.removingPercentEncoding ?? "VLESS"
        
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var params: [String: String] = [:]
        for item in queryItems {
            params[item.name] = item.value
        }
        
        return Proxy(
            name: name,
            type: .vless,
            host: host,
            port: port,
            settings: .vless(VLessSettings(
                uuid: uuid,
                flow: params["flow"],
                encryption: params["encryption"] ?? "none",
                network: params["type"] ?? "tcp",
                security: params["security"],
                sni: params["sni"],
                fingerprint: params["fp"],
                publicKey: params["pbk"],
                shortId: params["sid"],
                path: params["path"],
                wsHost: params["host"]
            ))
        )
    }
    
    // MARK: - Trojan Parser
    
    private static func parseTrojan(_ urlString: String) throws -> Proxy {
        guard let url = URL(string: urlString),
              let host = url.host,
              let port = url.port else {
            throw ProxyParseError.invalidFormat
        }
        
        let password = url.user ?? ""
        let name = url.fragment?.removingPercentEncoding ?? "Trojan"
        
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var params: [String: String] = [:]
        for item in queryItems {
            params[item.name] = item.value
        }
        
        return Proxy(
            name: name,
            type: .trojan,
            host: host,
            port: port,
            password: password,
            settings: .trojan(TrojanSettings(
                sni: params["sni"],
                fingerprint: params["fp"],
                alpn: params["alpn"]?.components(separatedBy: ",")
            ))
        )
    }
    
    // MARK: - SOCKS5 Parser
    
    private static func parseSocks5(_ urlString: String) throws -> Proxy {
        guard let url = URL(string: urlString),
              let host = url.host else {
            throw ProxyParseError.invalidFormat
        }
        
        let port = url.port ?? 1080
        let name = url.fragment?.removingPercentEncoding ?? "SOCKS5"
        
        return Proxy(
            name: name,
            type: .socks5,
            host: host,
            port: port,
            username: url.user,
            password: url.password,
            settings: .none
        )
    }
    
    // MARK: - HTTP Parser
    
    private static func parseHTTP(_ urlString: String) throws -> Proxy {
        guard let url = URL(string: urlString),
              let host = url.host else {
            throw ProxyParseError.invalidFormat
        }
        
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let name = url.fragment?.removingPercentEncoding ?? "HTTP"
        
        return Proxy(
            name: name,
            type: .http,
            host: host,
            port: port,
            username: url.user,
            password: url.password,
            settings: .none
        )
    }
}

// MARK: - Proxy Type

enum ProxyType: String, Codable, CaseIterable, Hashable {
    case socks5 = "SOCKS5"
    case http = "HTTP"
    case shadowsocks = "Shadowsocks"
    case vmess = "VMess"
    case vless = "VLESS"
    case trojan = "Trojan"
    
    var icon: String {
        switch self {
        case .socks5: return "network"
        case .http: return "globe"
        case .shadowsocks: return "lock.shield"
        case .vmess: return "bolt.shield"
        case .vless: return "bolt.shield.fill"
        case .trojan: return "shield.lefthalf.filled"
        }
    }
    
    var requiresXray: Bool {
        switch self {
        case .shadowsocks, .vmess, .vless, .trojan:
            return true
        case .socks5, .http:
            return false
        }
    }
}

// MARK: - Proxy Status

enum ProxyStatus: String, Codable, Hashable {
    case unknown = "Unknown"
    case checking = "Checking"
    case online = "Online"
    case offline = "Offline"
    case error = "Error"
    
    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .checking: return "arrow.triangle.2.circlepath"
        case .online: return "checkmark.circle.fill"
        case .offline: return "xmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .unknown: return "gray"
        case .checking: return "orange"
        case .online: return "green"
        case .offline: return "red"
        case .error: return "red"
        }
    }
}

// MARK: - Proxy Settings

enum ProxySettings: Codable, Hashable {
    case none
    case shadowsocks(ShadowsocksSettings)
    case vmess(VMessSettings)
    case vless(VLessSettings)
    case trojan(TrojanSettings)
}

// MARK: - Protocol-Specific Settings

struct ShadowsocksSettings: Codable, Hashable {
    var method: String // aes-256-gcm, chacha20-poly1305, 2022-blake3-aes-256-gcm, etc.
    var plugin: String?
    var pluginOpts: String?
    
    static let supportedMethods = [
        "aes-128-gcm",
        "aes-256-gcm",
        "chacha20-ietf-poly1305",
        "2022-blake3-aes-128-gcm",
        "2022-blake3-aes-256-gcm",
        "2022-blake3-chacha20-poly1305"
    ]
}

struct VMessSettings: Codable, Hashable {
    var uuid: String
    var alterId: Int
    var security: String? // auto, aes-128-gcm, chacha20-poly1305, none
    var network: String // tcp, ws, http, grpc, kcp, quic
    var path: String?
    var wsHost: String?
    var grpcServiceName: String?
}

struct VLessSettings: Codable, Hashable {
    var uuid: String
    var flow: String? // xtls-rprx-vision
    var encryption: String // none
    var network: String // tcp, ws, http, grpc, kcp, quic
    var security: String? // tls, reality
    var sni: String?
    var fingerprint: String?
    var publicKey: String? // for REALITY
    var shortId: String? // for REALITY
    var path: String?
    var wsHost: String?
}

struct TrojanSettings: Codable, Hashable {
    var sni: String?
    var fingerprint: String?
    var alpn: [String]?
}

// MARK: - Parse Error

enum ProxyParseError: LocalizedError, Equatable {
    case unsupportedProtocol
    case invalidBase64
    case invalidFormat
    case missingRequiredField(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProtocol:
            return "Unsupported proxy protocol"
        case .invalidBase64:
            return "Invalid base64 encoding"
        case .invalidFormat:
            return "Invalid proxy URL format"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}
