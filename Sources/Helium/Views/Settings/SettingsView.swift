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
    
    var body: some View {
        Form {
            Section {
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
            
            Section("DNS") {
                Text("DNS settings are managed per-profile through the proxy configuration.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Network")
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
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "atom")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Helium")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Open Source Anti-Detect Browser")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Version 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/brunusansi/helium")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/brunusansi/helium/issues")!)
                Link("Documentation", destination: URL(string: "https://github.com/brunusansi/helium/wiki")!)
            }
            
            Spacer()
            
            Text("Made with ❤️ by the community")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("MIT License")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
