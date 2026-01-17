import SwiftUI

@main
struct HeliumApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var proxyManager = ProxyManager()
    @StateObject private var xrayService = XrayService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(profileManager)
                .environmentObject(proxyManager)
                .environmentObject(xrayService)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            HeliumCommands()
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(profileManager)
                .environmentObject(proxyManager)
                .environmentObject(xrayService)
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: SidebarSection = .profiles
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var selectedProfileIds: Set<UUID> = []
    @Published var selectedFolderId: UUID?
    @Published var showingNewProfileSheet: Bool = false
    @Published var showingNewProxySheet: Bool = false
    @Published var showingImportSheet: Bool = false
    
    enum SidebarSection: Hashable {
        case profiles
        case proxies
        case tags
        case folder(UUID)
    }
}

// MARK: - Commands

struct HeliumCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Profile") {
                NotificationCenter.default.post(name: .newProfile, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Button("New Proxy") {
                NotificationCenter.default.post(name: .newProxy, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Import Profiles...") {
                NotificationCenter.default.post(name: .importProfiles, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command])
            
            Button("Export Profiles...") {
                NotificationCenter.default.post(name: .exportProfiles, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command])
        }
        
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newProfile = Notification.Name("newProfile")
    static let newProxy = Notification.Name("newProxy")
    static let importProfiles = Notification.Name("importProfiles")
    static let exportProfiles = Notification.Name("exportProfiles")
    static let toggleSidebar = Notification.Name("toggleSidebar")
}
