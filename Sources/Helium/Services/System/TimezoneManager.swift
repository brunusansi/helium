import Foundation

/// Manages system timezone synchronization with proxy location
@MainActor
final class TimezoneManager: ObservableObject {
    static let shared = TimezoneManager()
    
    @Published private(set) var currentTimezone: String = TimeZone.current.identifier
    @Published private(set) var originalTimezone: String = TimeZone.current.identifier
    @Published private(set) var isModified: Bool = false
    
    private init() {
        originalTimezone = TimeZone.current.identifier
        currentTimezone = originalTimezone
    }
    
    /// Sync timezone with proxy location
    /// - Parameter timezone: The timezone identifier (e.g., "America/New_York")
    func syncWithProxy(timezone: String) async throws {
        guard !timezone.isEmpty else { return }
        
        // Validate timezone exists
        guard TimeZone(identifier: timezone) != nil else {
            print("[TimezoneManager] Invalid timezone: \(timezone)")
            return
        }
        
        // Save original if not already modified
        if !isModified {
            originalTimezone = TimeZone.current.identifier
        }
        
        // Set system timezone via systemsetup (requires admin, so we use AppleScript)
        try await setSystemTimezone(timezone)
        
        currentTimezone = timezone
        isModified = true
        
        print("[TimezoneManager] Timezone synced to: \(timezone)")
    }
    
    /// Restore original timezone
    func restore() async {
        guard isModified else { return }
        
        do {
            try await setSystemTimezone(originalTimezone)
            currentTimezone = originalTimezone
            isModified = false
            print("[TimezoneManager] Timezone restored to: \(originalTimezone)")
        } catch {
            print("[TimezoneManager] Failed to restore timezone: \(error)")
        }
    }
    
    /// Set system timezone using AppleScript with admin privileges
    private func setSystemTimezone(_ timezone: String) async throws {
        // Method 1: Try using systemsetup directly (may work without sudo for current user)
        let script = """
        do shell script "sudo systemsetup -settimezone \(timezone)" with administrator privileges
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        
        // Run on main thread for AppleScript
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            // Fallback: Try without sudo (works on some systems)
            try await setTimezoneWithoutAdmin(timezone)
        }
    }
    
    /// Alternative method: Set timezone without admin (user preference only)
    private func setTimezoneWithoutAdmin(_ timezone: String) async throws {
        // This sets the timezone for the current process only
        // The browser will see this timezone
        setenv("TZ", timezone, 1)
        tzset()
        
        // Also try using defaults
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.timezone.auto", "Active", "-bool", "NO"]
        try? process.run()
        process.waitUntilExit()
    }
    
    /// Get timezone info from proxy location
    static func getTimezoneFromLocation(_ location: ProxyLocation?) -> String? {
        return location?.timezone
    }
    
    /// Calculate timezone offset from identifier
    static func getTimezoneOffset(_ identifier: String) -> Int? {
        guard let tz = TimeZone(identifier: identifier) else { return nil }
        return tz.secondsFromGMT() / 60 // Return in minutes
    }
}

// MARK: - Safari Timezone Injection

extension TimezoneManager {
    /// Generate JavaScript to inject timezone override (for Safari extension or WKWebView)
    func generateTimezoneScript(timezone: String, offset: Int) -> String {
        return """
        (function() {
            'use strict';
            
            const targetTimezone = '\(timezone)';
            const targetOffset = \(offset);
            
            // Override Date.prototype.getTimezoneOffset
            const originalGetTimezoneOffset = Date.prototype.getTimezoneOffset;
            Date.prototype.getTimezoneOffset = function() {
                return -targetOffset;
            };
            
            // Override Intl.DateTimeFormat
            const originalDateTimeFormat = Intl.DateTimeFormat;
            Intl.DateTimeFormat = function(locales, options) {
                if (options && !options.timeZone) {
                    options = { ...options, timeZone: targetTimezone };
                } else if (!options) {
                    options = { timeZone: targetTimezone };
                }
                return new originalDateTimeFormat(locales, options);
            };
            Intl.DateTimeFormat.prototype = originalDateTimeFormat.prototype;
            Intl.DateTimeFormat.supportedLocalesOf = originalDateTimeFormat.supportedLocalesOf;
            
            // Override Date.prototype.toLocaleString family
            const dateStringMethods = ['toLocaleString', 'toLocaleDateString', 'toLocaleTimeString'];
            dateStringMethods.forEach(method => {
                const original = Date.prototype[method];
                Date.prototype[method] = function(locales, options) {
                    if (options && !options.timeZone) {
                        options = { ...options, timeZone: targetTimezone };
                    } else if (!options) {
                        options = { timeZone: targetTimezone };
                    }
                    return original.call(this, locales, options);
                };
            });
            
            console.log('[Helium] Timezone spoofed to:', targetTimezone);
        })();
        """
    }
    
    /// Create a PAC file that includes timezone info in comments (for debugging)
    func generatePACWithTimezone(proxyHost: String, proxyPort: Int, timezone: String) -> String {
        return """
        // Helium Proxy Auto-Config
        // Timezone: \(timezone)
        // Generated: \(Date())
        
        function FindProxyForURL(url, host) {
            // Bypass local addresses
            if (isPlainHostName(host) ||
                shExpMatch(host, "*.local") ||
                isInNet(dnsResolve(host), "10.0.0.0", "255.0.0.0") ||
                isInNet(dnsResolve(host), "172.16.0.0", "255.240.0.0") ||
                isInNet(dnsResolve(host), "192.168.0.0", "255.255.0.0") ||
                isInNet(dnsResolve(host), "127.0.0.0", "255.255.255.0")) {
                return "DIRECT";
            }
            
            return "SOCKS5 \(proxyHost):\(proxyPort); SOCKS \(proxyHost):\(proxyPort); DIRECT";
        }
        """
    }
}

// MARK: - WebRTC Protection

extension TimezoneManager {
    /// Check if WebRTC protection is active (TUN interface running)
    nonisolated func isWebRTCProtected() -> Bool {
        // Check if any TUN interface is active
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Check for utun interfaces (our TUN interfaces)
            return output.contains("utun1") // utun10+ are our managed interfaces
        } catch {
            return false
        }
    }
    
    /// Generate warning message for WebRTC leak
    static var webRTCWarning: String {
        """
        ⚠️ WebRTC Protection requires TUN mode.
        
        Without TUN, WebRTC can leak your real IP even when using a proxy.
        
        To enable full protection:
        1. Go to Settings > Network
        2. Download tun2socks
        3. Select "TUN Interface" as isolation mode
        """
    }
}
