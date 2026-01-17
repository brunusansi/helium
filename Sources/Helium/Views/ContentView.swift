import SwiftUI

/// Main content view with sidebar navigation
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var proxyManager: ProxyManager
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .frame(minWidth: 220)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1000, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation {
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProfile)) { _ in
            appState.showingNewProfileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProxy)) { _ in
            appState.showingNewProxySheet = true
        }
        .sheet(isPresented: $appState.showingNewProfileSheet) {
            NewProfileSheet()
        }
        .sheet(isPresented: $appState.showingNewProxySheet) {
            NewProxySheet()
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .profiles:
            ProfileListView()
        case .proxies:
            ProxyListView()
        case .tags:
            TagsView()
        case .folder(let folderId):
            ProfileListView(folderId: folderId)
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var profileManager: ProfileManager
    
    var body: some View {
        List(selection: $appState.selectedSection) {
            Section {
                NavigationLink(value: AppState.SidebarSection.profiles) {
                    Label {
                        HStack {
                            Text("All Profiles")
                            Spacer()
                            Text("\(profileManager.profiles.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    } icon: {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                NavigationLink(value: AppState.SidebarSection.proxies) {
                    Label {
                        HStack {
                            Text("Proxies")
                            Spacer()
                            Text("\(profileManager.profiles.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    } icon: {
                        Image(systemName: "network")
                            .foregroundColor(.orange)
                    }
                }
                
                NavigationLink(value: AppState.SidebarSection.tags) {
                    Label("Tags", systemImage: "tag.fill")
                        .foregroundColor(.purple)
                }
            }
            
            if !profileManager.folders.isEmpty {
                Section("Folders") {
                    ForEach(profileManager.folders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                        NavigationLink(value: AppState.SidebarSection.folder(folder.id)) {
                            Label {
                                HStack {
                                    Text(folder.name)
                                    Spacer()
                                    Text("\(profileManager.profilesInFolder(folder.id).count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: folder.icon)
                                    .foregroundColor(.blue)
                            }
                        }
                        .contextMenu {
                            Button("Rename") {
                                // TODO: Rename folder
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                profileManager.deleteFolder(folder.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        appState.showingNewProfileSheet = true
                    } label: {
                        Label("New Profile", systemImage: "person.badge.plus")
                    }
                    
                    Button {
                        appState.showingNewProxySheet = true
                    } label: {
                        Label("New Proxy", systemImage: "network.badge.shield.half.filled")
                    }
                    
                    Divider()
                    
                    Button {
                        _ = profileManager.createFolder(name: "New Folder")
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - New Profile Sheet

struct NewProfileSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var proxyManager: ProxyManager
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedProxyId: UUID?
    @State private var selectedFolderId: UUID?
    @State private var startUrl: String = "https://www.google.com"
    @State private var fingerprintMode: FingerprintMode = .random
    
    enum FingerprintMode: String, CaseIterable {
        case random = "Random"
        case custom = "Custom"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Profile")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section {
                    TextField("Profile Name", text: $name)
                    TextField("Start URL", text: $startUrl)
                }
                
                Section("Proxy") {
                    Picker("Proxy", selection: $selectedProxyId) {
                        Text("No Proxy").tag(nil as UUID?)
                        ForEach(proxyManager.proxies) { proxy in
                            Text("\(proxy.name) (\(proxy.type.rawValue))").tag(proxy.id as UUID?)
                        }
                    }
                }
                
                Section("Folder") {
                    Picker("Folder", selection: $selectedFolderId) {
                        Text("No Folder").tag(nil as UUID?)
                        ForEach(profileManager.folders) { folder in
                            Label(folder.name, systemImage: folder.icon).tag(folder.id as UUID?)
                        }
                    }
                }
                
                Section("Fingerprint") {
                    Picker("Mode", selection: $fingerprintMode) {
                        ForEach(FingerprintMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if fingerprintMode == .random {
                        Text("A unique fingerprint will be generated automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Create Profile") {
                    createProfile()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
    
    private func createProfile() {
        var profile = Profile(
            name: name,
            folderId: selectedFolderId,
            proxyId: selectedProxyId,
            fingerprint: .random(),
            startUrl: startUrl
        )
        
        profileManager.updateProfile(profile)
        dismiss()
    }
}

// MARK: - New Proxy Sheet

struct NewProxySheet: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var importText: String = ""
    @State private var importResult: (success: Int, failed: Int)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Proxy")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste proxy URLs (one per line)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                
                Text("Supported formats: ss://, vmess://, vless://, trojan://, socks5://, http://")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let result = importResult {
                    HStack {
                        Image(systemName: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(result.failed == 0 ? .green : .orange)
                        Text("\(result.success) imported, \(result.failed) failed")
                    }
                    .font(.caption)
                }
            }
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Import") {
                    importProxies()
                }
                .keyboardShortcut(.return)
                .disabled(importText.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
    
    private func importProxies() {
        let result = proxyManager.importMultiple(importText)
        importResult = result
        
        if result.success > 0 && result.failed == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(ProfileManager())
        .environmentObject(ProxyManager())
        .environmentObject(XrayService())
        .frame(width: 1200, height: 800)
}
