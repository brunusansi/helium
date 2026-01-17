import SwiftUI

/// Settings view for app-wide configuration
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            FingerprintSettingsView()
                .tabItem {
                    Label("Fingerprint", systemImage: "hand.raised.fill")
                }
            
            NetworkSettingsView()
                .tabItem {
                    Label("Network", systemImage: "network")
                }
            
            XraySettingsView()
                .tabItem {
                    Label("Xray-core", systemImage: "bolt.shield")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("closeToTray") private var closeToTray = true
    @AppStorage("defaultBrowser") private var defaultBrowser = "safari"
    @AppStorage("theme") private var theme = "system"
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Close to menu bar", isOn: $closeToTray)
            }
            
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Section("Data") {
                LabeledContent("Profiles location") {
                    Text("~/Library/Application Support/Helium")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Open Data Folder") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Helium")
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Fingerprint Settings

struct FingerprintSettingsView: View {
    @AppStorage("defaultPlatform") private var defaultPlatform = "macIntel"
    @AppStorage("autoRandomize") private var autoRandomize = true
    @AppStorage("canvasProtection") private var canvasProtection = true
    @AppStorage("webglProtection") private var webglProtection = true
    @AppStorage("audioProtection") private var audioProtection = true
    @AppStorage("webrtcProtection") private var webrtcProtection = true
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-randomize fingerprint for new profiles", isOn: $autoRandomize)
                
                Picker("Default Platform", selection: $defaultPlatform) {
                    Text("macOS (Intel)").tag("macIntel")
                    Text("macOS (Apple Silicon)").tag("macArm")
                }
            }
            
            Section("Protection") {
                Toggle("Canvas fingerprint protection", isOn: $canvasProtection)
                Toggle("WebGL fingerprint protection", isOn: $webglProtection)
                Toggle("Audio fingerprint protection", isOn: $audioProtection)
                Toggle("WebRTC IP leak protection", isOn: $webrtcProtection)
            }
            
            Section {
                Text("These settings apply to newly created profiles. Existing profiles keep their current configuration.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Fingerprint")
    }
}

// MARK: - Network Settings

struct NetworkSettingsView: View {
    @AppStorage("proxyTimeout") private var proxyTimeout = 10
    @AppStorage("autoCheckProxies") private var autoCheckProxies = true
    @AppStorage("checkInterval") private var checkInterval = 30
    
    private var tunManager: TunManager { TunManager.shared }
    private var chromiumLauncher: ChromiumLauncher { ChromiumLauncher.shared }
    
    @State private var isDownloadingTun = false
    @State private var tunDownloadError: String?
    @State private var isTunInstalled = false
    @State private var isChromiumInstalled = false
    @State private var chromiumName = ""
    
    var body: some View {
        Form {
            Section("Proxy Settings") {
                LabeledContent("Connection timeout") {
                    Stepper("\(proxyTimeout) seconds", value: $proxyTimeout, in: 5...60, step: 5)
                }
                
                Toggle("Auto-check proxy status", isOn: $autoCheckProxies)
                
                if autoCheckProxies {
                    LabeledContent("Check interval") {
                        Stepper("\(checkInterval) minutes", value: $checkInterval, in: 5...120, step: 5)
                    }
                }
            }
            
            Section("Network Isolation (tun2socks)") {
                LabeledContent("Status") {
                    HStack {
                        if isDownloadingTun {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(isTunInstalled ? "Installed" : "Not installed")
                            .foregroundColor(isTunInstalled ? .green : .secondary)
                    }
                }
                
                if !isTunInstalled {
                    Button("Download tun2socks") {
                        downloadTun2Socks()
                    }
                    .disabled(isDownloadingTun)
                    
                    Text("Required for per-profile network isolation. Each Safari profile will have its own isolated proxy connection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let error = tunDownloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Link("tun2socks GitHub", destination: URL(string: "https://github.com/xjasonlyu/tun2socks")!)
                    .font(.caption)
            }
            
            Section("Browser Engines") {
                LabeledContent("Safari") {
                    Text("Built-in")
                        .foregroundColor(.green)
                }
                
                LabeledContent("Chromium") {
                    if isChromiumInstalled {
                        Text(chromiumName)
                            .foregroundColor(.green)
                    } else {
                        Text("Not found")
                            .foregroundColor(.secondary)
                    }
                }
                
                if !isChromiumInstalled {
                    Text("Install Chrome, Brave, Edge, or Vivaldi to use Chromium engine with per-profile proxy isolation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Network")
        .onAppear {
            Task { @MainActor in
                await refreshStatus()
            }
        }
    }
    
    @MainActor
    private func refreshStatus() async {
        tunManager.checkInstallation()
        isTunInstalled = tunManager.isTun2SocksInstalled
        chromiumLauncher.detectChromium()
        isChromiumInstalled = chromiumLauncher.isChromiumInstalled
        chromiumName = chromiumLauncher.detectedBrowserName
    }
    
    private func downloadTun2Socks() {
        isDownloadingTun = true
        tunDownloadError = nil
        
        Task {
            do {
                try await tunManager.downloadTun2Socks()
                await MainActor.run {
                    isDownloadingTun = false
                    isTunInstalled = true
                }
            } catch {
                await MainActor.run {
                    isDownloadingTun = false
                    tunDownloadError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Xray Settings

struct XraySettingsView: View {
    @StateObject private var xrayService = XrayService()
    @State private var isDownloading = false
    @State private var downloadError: String?
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack {
                        if isDownloading {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(xrayService.version ?? "Not installed")
                            .foregroundColor(xrayService.version != nil ? .green : .secondary)
                    }
                }
                
                if xrayService.version == nil {
                    Button("Download Xray-core") {
                        downloadXray()
                    }
                    .disabled(isDownloading)
                } else {
                    Button("Check for Updates") {
                        checkForUpdates()
                    }
                    .disabled(isDownloading)
                }
                
                if let error = downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Section("Info") {
                Text("Xray-core is required for VMess, VLESS, Trojan, and Shadowsocks protocols. It will be downloaded automatically when needed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("Xray-core GitHub", destination: URL(string: "https://github.com/XTLS/Xray-core")!)
            }
            
            Section("Active Connections") {
                if xrayService.activeConnections.isEmpty {
                    Text("No active connections")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(xrayService.activeConnections.values), id: \.profileId) { conn in
                        LabeledContent("Profile \(String(conn.profileId.uuidString.prefix(8)))") {
                            Text("Port \(conn.localPort)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Xray-core")
        .task {
            _ = try? await xrayService.getVersion()
        }
    }
    
    private func downloadXray() {
        isDownloading = true
        downloadError = nil
        
        Task {
            do {
                try await xrayService.downloadXrayCore()
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
        }
    }
    
    private func checkForUpdates() {
        // Same as download - will update if newer version available
        downloadXray()
    }
}

// MARK: - About View

struct AboutView: View {
    @State private var currentVersion: String = ""
    @State private var latestVersion: String?
    @State private var isCheckingUpdate = false
    @State private var updateAvailable = false
    @State private var releaseURL: URL?
    @State private var releaseNotes: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer()
                    .frame(height: 20)
                
                Image(systemName: "atom")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Helium")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Open Source Anti-Detect Browser")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text("Version \(currentVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if isCheckingUpdate {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if updateAvailable, let latest = latestVersion {
                        Text("→ \(latest) available")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
                
                // Update section
                VStack(spacing: 8) {
                    if updateAvailable, let url = releaseURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Download Update", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if let notes = releaseNotes {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .frame(maxWidth: 280)
                        }
                    } else {
                        Button {
                            checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCheckingUpdate)
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                    .frame(width: 180)
                
                VStack(spacing: 6) {
                    Link("GitHub Repository", destination: URL(string: "https://github.com/brunusansi/helium")!)
                    Link("Report an Issue", destination: URL(string: "https://github.com/brunusansi/helium/issues")!)
                }
                .font(.callout)
                
                Spacer()
                    .frame(height: 16)
                
                VStack(spacing: 4) {
                    Text("Made with ❤️ by the community")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("MIT License • 100% Open Source")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                    .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 350, minHeight: 400)
        .onAppear {
            loadCurrentVersion()
        }
    }
    
    private func loadCurrentVersion() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            currentVersion = version
        } else {
            currentVersion = "1.2.1" // Fallback
        }
    }
    
    private func checkForUpdates() {
        isCheckingUpdate = true
        updateAvailable = false
        
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/brunusansi/helium/releases/latest")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlUrl = json["html_url"] as? String else {
                    await MainActor.run { isCheckingUpdate = false }
                    return
                }
                
                let latest = tagName.replacingOccurrences(of: "v", with: "")
                let body = json["body"] as? String
                
                await MainActor.run {
                    latestVersion = latest
                    releaseURL = URL(string: htmlUrl)
                    releaseNotes = body?.components(separatedBy: "\n").first
                    
                    // Compare versions
                    if compareVersions(current: currentVersion, latest: latest) {
                        updateAvailable = true
                    }
                    
                    isCheckingUpdate = false
                }
            } catch {
                await MainActor.run {
                    isCheckingUpdate = false
                }
            }
        }
    }
    
    private func compareVersions(current: String, latest: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(currentParts.count, latestParts.count) {
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0
            
            if l > c { return true }
            if l < c { return false }
        }
        
        return false
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
