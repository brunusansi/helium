import Foundation
import WebKit

/// Stealthy fingerprint engine that doesn't trigger tampering detection
/// Uses Apple's native Safari fingerprint consistency instead of aggressive modification
final class FingerprintEngine {
    static let shared = FingerprintEngine()
    
    private init() {}
    
    /// Generate minimal, undetectable JavaScript injection
    /// Key principle: Don't modify canvas/webgl/audio - use Safari's native consistency
    func generateInjectionScript(config: FingerprintConfig, proxyInfo: ProxyGeoInfo? = nil) -> String {
        """
        (function() {
            'use strict';
            
            // ========================================
            // WebRTC IP Leak Protection (Critical)
            // ========================================
            
            \(generateWebRTCProtection(policy: config.webrtcPolicy))
            
            // ========================================
            // Timezone Sync (Match Proxy Location)
            // ========================================
            
            \(generateTimezoneOverride(config: config.timezone, proxyInfo: proxyInfo))
            
            // ========================================
            // Geolocation Sync (Match Proxy Location)
            // ========================================
            
            \(generateGeolocationOverride(config: config.geolocation, proxyInfo: proxyInfo))
            
            // ========================================
            // Language Override (Optional)
            // ========================================
            
            \(generateLanguageOverride(languages: config.languages))
            
        })();
        """
    }
    
    private func generateWebRTCProtection(policy: WebRTCPolicy) -> String {
        switch policy {
        case .disableNonProxiedUdp:
            // Most secure - prevents all WebRTC IP leaks
            return """
            (function() {
                if (typeof RTCPeerConnection !== 'undefined') {
                    const Original = RTCPeerConnection;
                    RTCPeerConnection = function(config, constraints) {
                        config = config || {};
                        config.iceServers = [];
                        config.iceTransportPolicy = 'relay';
                        return new Original(config, constraints);
                    };
                    RTCPeerConnection.prototype = Original.prototype;
                    Object.defineProperty(RTCPeerConnection, 'name', { value: 'RTCPeerConnection' });
                }
            })();
            """
        case .defaultPublicInterfaceOnly:
            return """
            (function() {
                if (typeof RTCPeerConnection !== 'undefined') {
                    const Original = RTCPeerConnection;
                    RTCPeerConnection = function(config, constraints) {
                        config = config || {};
                        if (config.iceServers) {
                            config.iceServers = config.iceServers.filter(s => 
                                !String(s.urls).includes('stun:')
                            );
                        }
                        return new Original(config, constraints);
                    };
                    RTCPeerConnection.prototype = Original.prototype;
                }
            })();
            """
        default:
            return "// WebRTC: Default policy"
        }
    }
    
    private func generateTimezoneOverride(config: TimezoneConfig, proxyInfo: ProxyGeoInfo?) -> String {
        var timezone: String
        var offset: Int
        
        switch config {
        case .auto:
            return "// Timezone: System default"
        case .matchProxy:
            if let info = proxyInfo {
                timezone = info.timezone
                offset = info.timezoneOffset
            } else {
                return "// Timezone: Awaiting proxy geo info"
            }
        case .custom(let tz, let off):
            timezone = tz
            offset = off
        }
        
        return """
        (function() {
            const TZ = '\(timezone)';
            const OFFSET = \(offset);
            
            // Override Intl.DateTimeFormat timezone
            const origResolved = Intl.DateTimeFormat.prototype.resolvedOptions;
            Intl.DateTimeFormat.prototype.resolvedOptions = function() {
                const r = origResolved.apply(this, arguments);
                r.timeZone = TZ;
                return r;
            };
            
            // Override Date.prototype.getTimezoneOffset
            Date.prototype.getTimezoneOffset = function() {
                return -OFFSET;
            };
        })();
        """
    }
    
    private func generateGeolocationOverride(config: GeolocationConfig, proxyInfo: ProxyGeoInfo?) -> String {
        var lat: Double
        var lon: Double
        var accuracy: Double = 100
        
        switch config {
        case .auto:
            return "// Geolocation: Real location"
        case .disabled:
            return """
            (function() {
                navigator.geolocation.getCurrentPosition = function(s, e) {
                    if (e) e({ code: 1, message: 'User denied Geolocation' });
                };
                navigator.geolocation.watchPosition = function(s, e) {
                    if (e) e({ code: 1, message: 'User denied Geolocation' });
                    return 0;
                };
            })();
            """
        case .matchProxy:
            if let info = proxyInfo {
                lat = info.latitude
                lon = info.longitude
                accuracy = 1000 // City-level accuracy
            } else {
                return "// Geolocation: Awaiting proxy geo info"
            }
        case .custom(let latitude, let longitude, let acc):
            lat = latitude
            lon = longitude
            accuracy = acc
        }
        
        return """
        (function() {
            const pos = {
                coords: {
                    latitude: \(lat),
                    longitude: \(lon),
                    accuracy: \(accuracy),
                    altitude: null,
                    altitudeAccuracy: null,
                    heading: null,
                    speed: null
                },
                timestamp: Date.now()
            };
            navigator.geolocation.getCurrentPosition = function(s) { s(pos); };
            navigator.geolocation.watchPosition = function(s) { s(pos); return 1; };
        })();
        """
    }
    
    private func generateLanguageOverride(languages: [String]) -> String {
        guard !languages.isEmpty else {
            return "// Language: System default"
        }
        
        let langArray = languages.map { "\"\($0)\"" }.joined(separator: ",")
        let primary = languages.first ?? "en-US"
        
        return """
        (function() {
            Object.defineProperty(navigator, 'language', { get: () => '\(primary)' });
            Object.defineProperty(navigator, 'languages', { get: () => [\(langArray)] });
        })();
        """
    }
    
    /// Create a WKUserScript for injection
    func createUserScript(config: FingerprintConfig, proxyInfo: ProxyGeoInfo? = nil) -> WKUserScript {
        let source = generateInjectionScript(config: config, proxyInfo: proxyInfo)
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}

// MARK: - Proxy Geo Info (fetched from IP geolocation API)

struct ProxyGeoInfo: Codable {
    let ip: String
    let country: String
    let countryCode: String
    let city: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let timezoneOffset: Int // minutes from UTC
    
    /// Fetch geo info for an IP using ip-api.com (free, no key required)
    static func fetch(proxyHost: String, proxyPort: Int) async throws -> ProxyGeoInfo {
        // Use the proxy to fetch our apparent IP, then get geo data
        // First, try to get IP info through a simple API
        let url = URL(string: "http://ip-api.com/json/?fields=status,message,country,countryCode,city,lat,lon,timezone,offset,query")!
        
        // Create session with proxy
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable: true,
            kCFNetworkProxiesSOCKSProxy: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: proxyPort
        ] as [AnyHashable: Any]
        
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "success" else {
            throw GeoError.apiFailed
        }
        
        return ProxyGeoInfo(
            ip: json["query"] as? String ?? "",
            country: json["country"] as? String ?? "",
            countryCode: json["countryCode"] as? String ?? "",
            city: json["city"] as? String ?? "",
            latitude: json["lat"] as? Double ?? 0,
            longitude: json["lon"] as? Double ?? 0,
            timezone: json["timezone"] as? String ?? "UTC",
            timezoneOffset: (json["offset"] as? Int ?? 0) / 60 // Convert seconds to minutes
        )
    }
    
    enum GeoError: Error {
        case apiFailed
    }
}
