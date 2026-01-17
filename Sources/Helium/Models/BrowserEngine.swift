import Foundation

/// Available browser engines for profile isolation
enum BrowserEngine: String, Codable, CaseIterable, Identifiable {
    case safariNative = "safari_native"
    case safariContainer = "safari_container"
    case chromium = "chromium"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .safariNative:
            return "Safari (Native)"
        case .safariContainer:
            return "Safari (Container)"
        case .chromium:
            return "Chromium"
        }
    }
    
    var icon: String {
        switch self {
        case .safariNative, .safariContainer:
            return "safari"
        case .chromium:
            return "globe"
        }
    }
    
    var description: String {
        switch self {
        case .safariNative:
            return "Best fingerprint stealth. Uses system proxy (shared across all profiles)."
        case .safariContainer:
            return "Safari with separate container per profile. Better isolation but shares system proxy."
        case .chromium:
            return "Full isolation with per-profile proxy. Each profile has its own data and proxy settings."
        }
    }
    
    var supportsPerProfileProxy: Bool {
        switch self {
        case .safariNative, .safariContainer:
            return false
        case .chromium:
            return true
        }
    }
    
    var fingerprintQuality: FingerprintQuality {
        switch self {
        case .safariNative:
            return .excellent
        case .safariContainer:
            return .good
        case .chromium:
            return .moderate
        }
    }
    
    var dataIsolation: DataIsolation {
        switch self {
        case .safariNative:
            return .shared
        case .safariContainer:
            return .containerBased
        case .chromium:
            return .fullyIsolated
        }
    }
}

enum FingerprintQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case moderate = "Moderate"
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "yellow"
        case .moderate: return "orange"
        }
    }
}

enum DataIsolation: String {
    case shared = "Shared"
    case containerBased = "Container-based"
    case fullyIsolated = "Fully Isolated"
}
