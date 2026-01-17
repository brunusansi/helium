import Foundation

/// Fingerprint configuration for browser profile isolation
struct FingerprintConfig: Codable, Hashable {
    // Hardware
    var cpuCores: Int
    var deviceMemory: Int
    var hardwareConcurrency: Int
    
    // Screen
    var screenWidth: Int
    var screenHeight: Int
    var colorDepth: Int
    var pixelRatio: Double
    
    // Platform
    var platform: PlatformType
    var vendor: String
    
    // WebGL
    var webglVendor: String
    var webglRenderer: String
    var webglUnmaskedVendor: String
    var webglUnmaskedRenderer: String
    
    // Canvas
    var canvasNoise: Double
    
    // Audio
    var audioNoise: Double
    
    // Timezone
    var timezone: TimezoneConfig
    
    // Geolocation
    var geolocation: GeolocationConfig
    
    // Language
    var languages: [String]
    var acceptLanguage: String
    
    // WebRTC
    var webrtcPolicy: WebRTCPolicy
    
    // Media devices
    var mediaDevices: MediaDevicesConfig
    
    // Fonts
    var fonts: [String]
    
    init(
        cpuCores: Int = 8,
        deviceMemory: Int = 8,
        hardwareConcurrency: Int = 8,
        screenWidth: Int = 1920,
        screenHeight: Int = 1080,
        colorDepth: Int = 24,
        pixelRatio: Double = 2.0,
        platform: PlatformType = .macIntel,
        vendor: String = "Apple Computer, Inc.",
        webglVendor: String = "WebKit",
        webglRenderer: String = "WebKit WebGL",
        webglUnmaskedVendor: String = "Apple Inc.",
        webglUnmaskedRenderer: String = "Apple M1",
        canvasNoise: Double = 0.0, // Disabled - causes detection
        audioNoise: Double = 0.0, // Disabled - causes detection
        timezone: TimezoneConfig = .matchProxy, // Auto-sync with proxy
        geolocation: GeolocationConfig = .matchProxy, // Auto-sync with proxy
        languages: [String] = ["en-US", "en"],
        acceptLanguage: String = "en-US,en;q=0.9",
        webrtcPolicy: WebRTCPolicy = .disableNonProxiedUdp,
        mediaDevices: MediaDevicesConfig = .default,
        fonts: [String] = []
    ) {
        self.cpuCores = cpuCores
        self.deviceMemory = deviceMemory
        self.hardwareConcurrency = hardwareConcurrency
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.colorDepth = colorDepth
        self.pixelRatio = pixelRatio
        self.platform = platform
        self.vendor = vendor
        self.webglVendor = webglVendor
        self.webglRenderer = webglRenderer
        self.webglUnmaskedVendor = webglUnmaskedVendor
        self.webglUnmaskedRenderer = webglUnmaskedRenderer
        self.canvasNoise = canvasNoise
        self.audioNoise = audioNoise
        self.timezone = timezone
        self.geolocation = geolocation
        self.languages = languages
        self.acceptLanguage = acceptLanguage
        self.webrtcPolicy = webrtcPolicy
        self.mediaDevices = mediaDevices
        self.fonts = fonts
    }
    
    /// Generate a random fingerprint configuration
    static func random() -> FingerprintConfig {
        let cpuOptions = [4, 8, 12, 16]
        let memoryOptions = [4, 8, 16]
        let screenOptions = [
            (1920, 1080), (2560, 1440), (1440, 900),
            (1680, 1050), (2560, 1600), (1920, 1200)
        ]
        let gpuOptions = [
            "Apple M1", "Apple M1 Pro", "Apple M1 Max", "Apple M2",
            "Apple M2 Pro", "Apple M2 Max", "Apple M3", "Apple M3 Pro"
        ]
        
        let selectedScreen = screenOptions.randomElement()!
        let selectedGpu = gpuOptions.randomElement()!
        let selectedCores = cpuOptions.randomElement()!
        
        return FingerprintConfig(
            cpuCores: selectedCores,
            deviceMemory: memoryOptions.randomElement()!,
            hardwareConcurrency: selectedCores,
            screenWidth: selectedScreen.0,
            screenHeight: selectedScreen.1,
            colorDepth: 24,
            pixelRatio: [1.0, 2.0].randomElement()!,
            platform: .macIntel,
            vendor: "Apple Computer, Inc.",
            webglVendor: "WebKit",
            webglRenderer: "WebKit WebGL",
            webglUnmaskedVendor: "Apple Inc.",
            webglUnmaskedRenderer: selectedGpu,
            canvasNoise: 0.0, // Disabled - native Safari fingerprint
            audioNoise: 0.0,  // Disabled - native Safari fingerprint
            timezone: .matchProxy, // Auto-sync with proxy location
            geolocation: .matchProxy, // Auto-sync with proxy location
            languages: ["en-US", "en"],
            acceptLanguage: "en-US,en;q=0.9",
            webrtcPolicy: .disableNonProxiedUdp,
            mediaDevices: .random(),
            fonts: Self.randomFonts()
        )
    }
    
    private static func randomFonts() -> [String] {
        let allFonts = [
            "Arial", "Helvetica", "Times New Roman", "Georgia",
            "Verdana", "Trebuchet MS", "Courier New", "Comic Sans MS",
            "Impact", "Lucida Grande", "Palatino", "Menlo",
            "Monaco", "SF Pro", "SF Mono", "Avenir",
            "Optima", "Futura", "Gill Sans", "Baskerville"
        ]
        let count = Int.random(in: 10...15)
        return Array(allFonts.shuffled().prefix(count))
    }
}

// MARK: - Platform Type

enum PlatformType: String, Codable, CaseIterable, Hashable {
    case macIntel = "MacIntel"
    case macArm = "MacARM"
    
    var navigator: String {
        switch self {
        case .macIntel: return "MacIntel"
        case .macArm: return "MacARM"
        }
    }
}

// MARK: - Timezone Config

enum TimezoneConfig: Codable, Hashable {
    case auto
    case matchProxy
    case custom(String, Int) // timezone identifier, offset in minutes
    
    var displayName: String {
        switch self {
        case .auto: return "Auto (System)"
        case .matchProxy: return "Match Proxy Location"
        case .custom(let tz, _): return tz
        }
    }
}

// MARK: - Geolocation Config

enum GeolocationConfig: Codable, Hashable {
    case auto
    case matchProxy
    case disabled
    case custom(latitude: Double, longitude: Double, accuracy: Double)
    
    var displayName: String {
        switch self {
        case .auto: return "Auto (Real)"
        case .matchProxy: return "Match Proxy Location"
        case .disabled: return "Disabled"
        case .custom(let lat, let lon, _): return "\(lat), \(lon)"
        }
    }
}

// MARK: - WebRTC Policy

enum WebRTCPolicy: String, Codable, CaseIterable, Hashable {
    case `default` = "default"
    case defaultPublicAndPrivateInterfaces = "default_public_and_private_interfaces"
    case defaultPublicInterfaceOnly = "default_public_interface_only"
    case disableNonProxiedUdp = "disable_non_proxied_udp"
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .defaultPublicAndPrivateInterfaces: return "Public & Private"
        case .defaultPublicInterfaceOnly: return "Public Only"
        case .disableNonProxiedUdp: return "Disable Non-Proxied UDP (Recommended)"
        }
    }
}

// MARK: - Media Devices Config

struct MediaDevicesConfig: Codable, Hashable {
    var audioInputs: Int
    var audioOutputs: Int
    var videoInputs: Int
    
    static let `default` = MediaDevicesConfig(audioInputs: 1, audioOutputs: 1, videoInputs: 1)
    
    static func random() -> MediaDevicesConfig {
        MediaDevicesConfig(
            audioInputs: Int.random(in: 0...2),
            audioOutputs: Int.random(in: 1...2),
            videoInputs: Int.random(in: 0...1)
        )
    }
}

// MARK: - Predefined Locations

struct GeoLocation: Identifiable, Hashable {
    let id = UUID()
    let city: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let timezoneOffset: Int
    
    static let locations: [GeoLocation] = [
        GeoLocation(city: "New York", country: "United States", countryCode: "US", latitude: 40.7128, longitude: -74.0060, timezone: "America/New_York", timezoneOffset: -300),
        GeoLocation(city: "Los Angeles", country: "United States", countryCode: "US", latitude: 34.0522, longitude: -118.2437, timezone: "America/Los_Angeles", timezoneOffset: -480),
        GeoLocation(city: "London", country: "United Kingdom", countryCode: "GB", latitude: 51.5074, longitude: -0.1278, timezone: "Europe/London", timezoneOffset: 0),
        GeoLocation(city: "Paris", country: "France", countryCode: "FR", latitude: 48.8566, longitude: 2.3522, timezone: "Europe/Paris", timezoneOffset: 60),
        GeoLocation(city: "Berlin", country: "Germany", countryCode: "DE", latitude: 52.5200, longitude: 13.4050, timezone: "Europe/Berlin", timezoneOffset: 60),
        GeoLocation(city: "Tokyo", country: "Japan", countryCode: "JP", latitude: 35.6762, longitude: 139.6503, timezone: "Asia/Tokyo", timezoneOffset: 540),
        GeoLocation(city: "Singapore", country: "Singapore", countryCode: "SG", latitude: 1.3521, longitude: 103.8198, timezone: "Asia/Singapore", timezoneOffset: 480),
        GeoLocation(city: "Sydney", country: "Australia", countryCode: "AU", latitude: -33.8688, longitude: 151.2093, timezone: "Australia/Sydney", timezoneOffset: 600),
        GeoLocation(city: "São Paulo", country: "Brazil", countryCode: "BR", latitude: -23.5505, longitude: -46.6333, timezone: "America/Sao_Paulo", timezoneOffset: -180),
        GeoLocation(city: "Dubai", country: "UAE", countryCode: "AE", latitude: 25.2048, longitude: 55.2708, timezone: "Asia/Dubai", timezoneOffset: 240),
        // Add more as needed
    ]
}

// MARK: - Predefined Languages

struct BrowserLanguage: Identifiable, Hashable {
    let id = UUID()
    let code: String
    let name: String
    let acceptLanguage: String
    
    static let languages: [BrowserLanguage] = [
        BrowserLanguage(code: "en-US", name: "English (US)", acceptLanguage: "en-US,en;q=0.9"),
        BrowserLanguage(code: "en-GB", name: "English (UK)", acceptLanguage: "en-GB,en;q=0.9"),
        BrowserLanguage(code: "es-ES", name: "Spanish (Spain)", acceptLanguage: "es-ES,es;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "pt-BR", name: "Portuguese (Brazil)", acceptLanguage: "pt-BR,pt;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "fr-FR", name: "French", acceptLanguage: "fr-FR,fr;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "de-DE", name: "German", acceptLanguage: "de-DE,de;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "it-IT", name: "Italian", acceptLanguage: "it-IT,it;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "ja-JP", name: "Japanese", acceptLanguage: "ja-JP,ja;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "zh-CN", name: "Chinese (Simplified)", acceptLanguage: "zh-CN,zh;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "ko-KR", name: "Korean", acceptLanguage: "ko-KR,ko;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "ru-RU", name: "Russian", acceptLanguage: "ru-RU,ru;q=0.9,en;q=0.8"),
        BrowserLanguage(code: "ar-SA", name: "Arabic", acceptLanguage: "ar-SA,ar;q=0.9,en;q=0.8"),
        // Add more as needed
    ]
}
