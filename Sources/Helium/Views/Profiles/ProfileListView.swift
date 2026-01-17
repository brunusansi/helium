import SwiftUI

/// List view for profiles with selection and actions
struct ProfileListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var xrayService: XrayService
    
    let folderId: UUID?
    
    private var networkIsolator: NetworkIsolator { NetworkIsolator.shared }
    private var chromiumLauncher: ChromiumLauncher { ChromiumLauncher.shared }
    
    @State private var sortOrder: SortOrder = .name
    @State private var selectedProfile: Profile?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var hoveredProfileId: UUID?
    @State private var launchError: String?
    @State private var showingLaunchError: Bool = false
    @State private var activeProfileIds: Set<UUID> = []
    
    init(folderId: UUID? = nil) {
        self.folderId = folderId
    }
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case lastUsed = "Last Used"
        case created = "Created"
    }
    
    private var filteredProfiles: [Profile] {
        var profiles = folderId != nil 
            ? profileManager.profilesInFolder(folderId)
            : profileManager.profiles
        
        if !appState.searchText.isEmpty {
            profiles = profiles.filter { 
                $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
                $0.notes.localizedCaseInsensitiveContains(appState.searchText)
            }
        }
        
        switch sortOrder {
        case .name:
            profiles.sort { $0.name < $1.name }
        case .lastUsed:
            profiles.sort { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
        case .created:
            profiles.sort { $0.createdAt > $1.createdAt }
        }
        
        return profiles
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ProfileListToolbar(
                searchText: $appState.searchText,
                sortOrder: $sortOrder,
                selectedCount: appState.selectedProfileIds.count,
                onNewProfile: { appState.showingNewProfileSheet = true },
                onDeleteSelected: { showingDeleteConfirmation = true }
            )
            
            Divider()
            
            if filteredProfiles.isEmpty {
                EmptyProfilesView(hasSearch: !appState.searchText.isEmpty)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isSelected: appState.selectedProfileIds.contains(profile.id),
                                isHovered: hoveredProfileId == profile.id,
                                isActive: activeProfileIds.contains(profile.id),
                                proxy: profile.proxyId.flatMap { proxyManager.getProxy($0) },
                                onLaunch: { launchProfile(profile) },
                                onStop: { stopProfile(profile) },
                                onEdit: { selectedProfile = profile },
                                onDuplicate: { duplicateProfile(profile) },
                                onDelete: { deleteProfile(profile) }
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    toggleSelection(profile.id)
                                }
                            }
                            .onHover { isHovered in
                                hoveredProfileId = isHovered ? profile.id : nil
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(folderId.flatMap { profileManager.getFolder($0)?.name } ?? "All Profiles")
        .sheet(item: $selectedProfile) { profile in
            ProfileEditSheet(profile: profile)
        }
        .alert("Delete Profiles", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                profileManager.deleteProfiles(appState.selectedProfileIds)
                appState.selectedProfileIds.removeAll()
            }
        } message: {
            Text("Are you sure you want to delete \(appState.selectedProfileIds.count) profile(s)? This action cannot be undone.")
        }
        .alert("Launch Error", isPresented: $showingLaunchError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(launchError ?? "Unknown error occurred")
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if appState.selectedProfileIds.contains(id) {
            appState.selectedProfileIds.remove(id)
        } else {
            appState.selectedProfileIds.insert(id)
        }
    }
    
    private func launchProfile(_ profile: Profile) {
        let proxy = profile.proxyId.flatMap { proxyManager.getProxy($0) }
        
        Task {
            do {
                switch profile.browserEngine {
                case .safariNative, .safariContainer:
                    // Use NetworkIsolator for Safari with proper network isolation
                    try await networkIsolator.launchProfile(
                        profile: profile,
                        proxy: proxy,
                        isolationMode: profile.isolationMode
                    )
                    
                case .chromium:
                    // Chromium handles its own proxy via command line args
                    try await chromiumLauncher.launchProfile(
                        profile: profile,
                        proxy: proxy,
                        xrayService: networkIsolator.xray
                    )
                }
                
                await MainActor.run {
                    activeProfileIds.insert(profile.id)
                }
                profileManager.launchProfile(profile.id)
            } catch {
                await MainActor.run {
                    launchError = error.localizedDescription
                    showingLaunchError = true
                }
            }
        }
    }
    
    private func stopProfile(_ profile: Profile) {
        Task {
            switch profile.browserEngine {
            case .safariNative, .safariContainer:
                await networkIsolator.stopProfile(profileId: profile.id)
            case .chromium:
                chromiumLauncher.stopProfile(profileId: profile.id, xrayService: networkIsolator.xray)
            }
            
            await MainActor.run {
                activeProfileIds.remove(profile.id)
            }
            profileManager.stopProfile(profile.id)
        }
    }
    
    private func duplicateProfile(_ profile: Profile) {
        _ = profileManager.duplicateProfile(profile.id)
    }
    
    private func deleteProfile(_ profile: Profile) {
        profileManager.deleteProfile(profile.id)
        appState.selectedProfileIds.remove(profile.id)
    }
}

// MARK: - Profile List Toolbar

struct ProfileListToolbar: View {
    @Binding var searchText: String
    @Binding var sortOrder: ProfileListView.SortOrder
    let selectedCount: Int
    let onNewProfile: () -> Void
    let onDeleteSelected: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search profiles...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 300)
            
            Spacer()
            
            if selectedCount > 0 {
                Text("\(selectedCount) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(role: .destructive) {
                    onDeleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            
            // Sort
            Menu {
                ForEach(ProfileListView.SortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOrder.rawValue)
                }
            }
            .menuStyle(.borderlessButton)
            
            // New Profile
            Button {
                onNewProfile()
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: Profile
    let isSelected: Bool
    let isHovered: Bool
    let isActive: Bool
    let proxy: Proxy?
    let onLaunch: () -> Void
    let onStop: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Color indicator
                Circle()
                    .fill(colorForProfile(profile.color))
                    .frame(width: 10, height: 10)
                
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Status badge
                if isActive {
                    StatusBadge(status: .running)
                } else {
                    StatusBadge(status: .ready)
                }
            }
            
            // Proxy info
            HStack {
                Image(systemName: proxy != nil ? "network" : "network.slash")
                    .font(.caption)
                    .foregroundColor(proxy != nil ? .green : .secondary)
                
                Text(proxy?.name ?? "No Proxy")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                if let latency = proxy?.lastLatency {
                    Text("\(latency)ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Fingerprint summary
            HStack(spacing: 8) {
                FingerprintBadge(icon: "cpu", value: "\(profile.fingerprint.cpuCores) cores")
                FingerprintBadge(icon: "memorychip", value: "\(profile.fingerprint.deviceMemory)GB")
                FingerprintBadge(icon: "display", value: "\(profile.fingerprint.screenWidth)×\(profile.fingerprint.screenHeight)")
            }
            
            Divider()
            
            // Actions
            HStack {
                if isActive {
                    Button {
                        onStop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        onLaunch()
                    } label: {
                        Label("Launch", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
                
                Menu {
                    Button { onEdit() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button { onDuplicate() } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.15 : 0.08), radius: isHovered ? 8 : 4, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
    
    private func colorForProfile(_ color: ProfileColor) -> Color {
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ProfileStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor)
        .cornerRadius(4)
    }
    
    private var backgroundColor: Color {
        switch status {
        case .ready: return .green.opacity(0.2)
        case .running: return .blue.opacity(0.2)
        case .syncing: return .orange.opacity(0.2)
        case .error: return .red.opacity(0.2)
        }
    }
}

// MARK: - Fingerprint Badge

struct FingerprintBadge: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(value)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Empty State

struct EmptyProfilesView: View {
    let hasSearch: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearch ? "magnifyingglass" : "person.crop.rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(hasSearch ? "No profiles match your search" : "No profiles yet")
                .font(.title3)
                .foregroundColor(.secondary)
            
            if !hasSearch {
                Text("Create your first profile to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Profile Edit Sheet

struct ProfileEditSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var proxyManager: ProxyManager
    @Environment(\.dismiss) private var dismiss
    
    let profile: Profile
    
    @State private var name: String
    @State private var notes: String
    @State private var startUrl: String
    @State private var selectedProxyId: UUID?
    @State private var selectedColor: ProfileColor
    @State private var selectedBrowserEngine: BrowserEngine
    @State private var selectedIsolationMode: NetworkIsolationMode
    @State private var fingerprint: FingerprintConfig
    
    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _notes = State(initialValue: profile.notes)
        _startUrl = State(initialValue: profile.startUrl)
        _selectedProxyId = State(initialValue: profile.proxyId)
        _selectedColor = State(initialValue: profile.color)
        _selectedBrowserEngine = State(initialValue: profile.browserEngine)
        _selectedIsolationMode = State(initialValue: profile.isolationMode)
        _fingerprint = State(initialValue: profile.fingerprint)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Profile")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Start URL", text: $startUrl)
                    TextEditor(text: $notes)
                        .frame(height: 60)
                }
                
                Section("Appearance") {
                    Picker("Color", selection: $selectedColor) {
                        ForEach(ProfileColor.allCases, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(colorValue(color))
                                    .frame(width: 12, height: 12)
                                Text(color.rawValue.capitalized)
                            }
                            .tag(color)
                        }
                    }
                }
                
                Section("Proxy") {
                    Picker("Proxy", selection: $selectedProxyId) {
                        Text("No Proxy").tag(nil as UUID?)
                        ForEach(proxyManager.proxies) { proxy in
                            Text("\(proxy.name) (\(proxy.type.rawValue))").tag(proxy.id as UUID?)
                        }
                    }
                }
                
                Section("Browser Engine") {
                    Picker("Engine", selection: $selectedBrowserEngine) {
                        ForEach(BrowserEngine.allCases) { engine in
                            HStack {
                                Image(systemName: engine.icon)
                                Text(engine.displayName)
                            }
                            .tag(engine)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    
                    // Description of selected engine
                    Text(selectedBrowserEngine.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Show warning for proxy isolation
                    if selectedProxyId != nil && !selectedBrowserEngine.supportsPerProfileProxy {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("This engine uses system proxy. Multiple profiles will share the same proxy.")
                                .font(.caption)
                        }
                    }
                    
                    // Fingerprint quality indicator
                    HStack {
                        Text("Fingerprint Stealth:")
                            .font(.caption)
                        Text(selectedBrowserEngine.fingerprintQuality.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(fingerprintColor(selectedBrowserEngine.fingerprintQuality))
                    }
                    
                    HStack {
                        Text("Data Isolation:")
                            .font(.caption)
                        Text(selectedBrowserEngine.dataIsolation.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                // Only show network isolation for Safari engines
                if selectedBrowserEngine != .chromium {
                    Section("Network Isolation") {
                        Picker("Mode", selection: $selectedIsolationMode) {
                            ForEach(NetworkIsolationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        
                        Text(selectedIsolationMode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if selectedIsolationMode == .perProfileTun {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Requires tun2socks. Install from Settings > Network.")
                                    .font(.caption)
                            }
                            
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Each profile will have its own isolated proxy!")
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Section("Fingerprint") {
                    LabeledContent("CPU Cores") {
                        Picker("", selection: $fingerprint.cpuCores) {
                            ForEach([4, 8, 12, 16], id: \.self) { cores in
                                Text("\(cores)").tag(cores)
                            }
                        }
                        .frame(width: 80)
                    }
                    
                    LabeledContent("Memory") {
                        Picker("", selection: $fingerprint.deviceMemory) {
                            ForEach([4, 8, 16], id: \.self) { memory in
                                Text("\(memory) GB").tag(memory)
                            }
                        }
                        .frame(width: 80)
                    }
                    
                    LabeledContent("Screen") {
                        Text("\(fingerprint.screenWidth) × \(fingerprint.screenHeight)")
                            .foregroundColor(.secondary)
                    }
                    
                    LabeledContent("WebRTC") {
                        Picker("", selection: $fingerprint.webrtcPolicy) {
                            ForEach(WebRTCPolicy.allCases, id: \.self) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                    }
                    
                    Button("Regenerate Fingerprint") {
                        fingerprint = .random()
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Save") {
                    saveProfile()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 700)
    }
    
    private func saveProfile() {
        var updated = profile
        updated.name = name
        updated.notes = notes
        updated.startUrl = startUrl
        updated.proxyId = selectedProxyId
        updated.color = selectedColor
        updated.browserEngine = selectedBrowserEngine
        updated.isolationMode = selectedIsolationMode
        updated.fingerprint = fingerprint
        profileManager.updateProfile(updated)
        dismiss()
    }
    
    private func colorValue(_ color: ProfileColor) -> Color {
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }
    
    private func fingerprintColor(_ quality: FingerprintQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .yellow
        case .moderate: return .orange
        }
    }
}

#Preview {
    ProfileListView()
        .environmentObject(AppState())
        .environmentObject(ProfileManager())
        .environmentObject(ProxyManager())
        .frame(width: 900, height: 600)
}
