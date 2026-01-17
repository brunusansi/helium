import SwiftUI

/// List view for managing proxies
struct ProxyListView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @EnvironmentObject var appState: AppState
    
    @State private var selectedProxyIds: Set<UUID> = []
    @State private var showingDeleteConfirmation: Bool = false
    @State private var editingProxy: Proxy?
    @State private var sortOrder: SortOrder = .name
    
    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case type = "Type"
        case latency = "Latency"
        case status = "Status"
    }
    
    private var filteredProxies: [Proxy] {
        var proxies = proxyManager.proxies
        
        if !appState.searchText.isEmpty {
            proxies = proxies.filter {
                $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
                $0.host.localizedCaseInsensitiveContains(appState.searchText) ||
                ($0.country?.localizedCaseInsensitiveContains(appState.searchText) ?? false)
            }
        }
        
        switch sortOrder {
        case .name:
            proxies.sort { $0.name < $1.name }
        case .type:
            proxies.sort { $0.type.rawValue < $1.type.rawValue }
        case .latency:
            proxies.sort { ($0.lastLatency ?? Int.max) < ($1.lastLatency ?? Int.max) }
        case .status:
            proxies.sort { $0.status.rawValue < $1.status.rawValue }
        }
        
        return proxies
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ProxyListToolbar(
                searchText: $appState.searchText,
                sortOrder: $sortOrder,
                selectedCount: selectedProxyIds.count,
                onAddProxy: { appState.showingNewProxySheet = true },
                onCheckAll: { Task { await proxyManager.checkAllProxies() } },
                onDeleteSelected: { showingDeleteConfirmation = true }
            )
            
            Divider()
            
            if filteredProxies.isEmpty {
                EmptyProxiesView(hasSearch: !appState.searchText.isEmpty)
            } else {
                List(selection: $selectedProxyIds) {
                    ForEach(filteredProxies) { proxy in
                        ProxyRow(
                            proxy: proxy,
                            isChecking: proxyManager.checkingProxies.contains(proxy.id),
                            onCheck: { Task { await proxyManager.checkProxy(proxy.id) } },
                            onEdit: { editingProxy = proxy },
                            onDelete: { proxyManager.deleteProxy(proxy.id) }
                        )
                        .tag(proxy.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Proxies")
        .sheet(item: $editingProxy) { proxy in
            ProxyEditSheet(proxy: proxy)
        }
        .alert("Delete Proxies", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                proxyManager.deleteProxies(selectedProxyIds)
                selectedProxyIds.removeAll()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedProxyIds.count) proxy(s)?")
        }
    }
}

// MARK: - Proxy List Toolbar

struct ProxyListToolbar: View {
    @Binding var searchText: String
    @Binding var sortOrder: ProxyListView.SortOrder
    let selectedCount: Int
    let onAddProxy: () -> Void
    let onCheckAll: () -> Void
    let onDeleteSelected: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search proxies...", text: $searchText)
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
            
            // Check all
            Button {
                onCheckAll()
            } label: {
                Label("Check All", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            
            // Sort
            Menu {
                ForEach(ProxyListView.SortOrder.allCases, id: \.self) { order in
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
            
            // Add Proxy
            Button {
                onAddProxy()
            } label: {
                Label("Add Proxy", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Proxy Row

struct ProxyRow: View {
    let proxy: Proxy
    let isChecking: Bool
    let onCheck: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: proxy.type.icon)
                .font(.title3)
                .foregroundColor(typeColor)
                .frame(width: 32)
            
            // Name and host
            VStack(alignment: .leading, spacing: 2) {
                Text(proxy.name)
                    .font(.headline)
                Text("\(proxy.host):\(proxy.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Country
            if let country = proxy.country {
                HStack(spacing: 4) {
                    if let code = proxy.countryCode {
                        Text(flagEmoji(for: code))
                    }
                    Text(country)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Latency
            if let latency = proxy.lastLatency {
                Text("\(latency)ms")
                    .font(.caption)
                    .foregroundColor(latencyColor(latency))
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
            
            // Status
            ProxyStatusBadge(status: proxy.status, isChecking: isChecking)
            
            // Actions
            HStack(spacing: 8) {
                Button {
                    onCheck()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .disabled(isChecking)
                
                Menu {
                    Button { onEdit() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button { copyToClipboard() } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
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
        .padding(.vertical, 4)
    }
    
    private var typeColor: Color {
        switch proxy.type {
        case .shadowsocks: return .purple
        case .vmess: return .blue
        case .vless: return .cyan
        case .trojan: return .red
        case .socks5: return .orange
        case .http: return .green
        }
    }
    
    private func latencyColor(_ latency: Int) -> Color {
        if latency < 100 { return .green }
        if latency < 300 { return .yellow }
        return .red
    }
    
    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        var emoji = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                emoji.append(Character(unicode))
            }
        }
        return emoji
    }
    
    private func copyToClipboard() {
        // Generate proxy URL and copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(proxy.type.rawValue.lowercased())://\(proxy.host):\(proxy.port)", forType: .string)
    }
}

// MARK: - Proxy Status Badge

struct ProxyStatusBadge: View {
    let status: ProxyStatus
    let isChecking: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            if isChecking {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: status.icon)
                    .font(.caption2)
            }
            Text(isChecking ? "Checking" : status.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .cornerRadius(4)
        .frame(width: 80)
    }
    
    private var backgroundColor: Color {
        if isChecking { return .orange.opacity(0.2) }
        switch status {
        case .unknown: return .gray.opacity(0.2)
        case .checking: return .orange.opacity(0.2)
        case .online: return .green.opacity(0.2)
        case .offline: return .red.opacity(0.2)
        case .error: return .red.opacity(0.2)
        }
    }
}

// MARK: - Empty State

struct EmptyProxiesView: View {
    let hasSearch: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearch ? "magnifyingglass" : "network")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(hasSearch ? "No proxies match your search" : "No proxies yet")
                .font(.title3)
                .foregroundColor(.secondary)
            
            if !hasSearch {
                Text("Add proxies to route your traffic through different locations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Proxy Edit Sheet

struct ProxyEditSheet: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @Environment(\.dismiss) private var dismiss
    
    let proxy: Proxy
    
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    
    init(proxy: Proxy) {
        self.proxy = proxy
        _name = State(initialValue: proxy.name)
        _host = State(initialValue: proxy.host)
        _port = State(initialValue: String(proxy.port))
        _username = State(initialValue: proxy.username ?? "")
        _password = State(initialValue: proxy.password ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Proxy")
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
                    
                    LabeledContent("Type") {
                        Text(proxy.type.rawValue)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Connection") {
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                }
                
                Section("Authentication") {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Save") {
                    saveProxy()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || host.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
    
    private func saveProxy() {
        var updated = proxy
        updated.name = name
        updated.host = host
        updated.port = Int(port) ?? proxy.port
        updated.username = username.isEmpty ? nil : username
        updated.password = password.isEmpty ? nil : password
        proxyManager.updateProxy(updated)
        dismiss()
    }
}

// MARK: - Tags View

struct TagsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @State private var newTagName: String = ""
    @State private var selectedColor: TagColor = .blue
    
    var body: some View {
        VStack(spacing: 0) {
            // Add tag form
            HStack {
                TextField("New tag name...", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                
                Picker("Color", selection: $selectedColor) {
                    ForEach(TagColor.allCases, id: \.self) { color in
                        Text(color.rawValue.capitalized)
                            .foregroundColor(colorValue(color))
                            .tag(color)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                Button("Add") {
                    if !newTagName.isEmpty {
                        _ = profileManager.createTag(name: newTagName, color: selectedColor)
                        newTagName = ""
                    }
                }
                .disabled(newTagName.isEmpty)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            if profileManager.tags.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tag")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No tags yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(profileManager.tags) { tag in
                        HStack {
                            Circle()
                                .fill(colorValue(tag.color))
                                .frame(width: 12, height: 12)
                            
                            Text(tag.name)
                            
                            Spacer()
                            
                            Text("\(profileManager.profilesWithTag(tag.id).count) profiles")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(role: .destructive) {
                                profileManager.deleteTag(tag.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Tags")
    }
    
    private func colorValue(_ color: TagColor) -> Color {
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
        case .gray: return .gray
        }
    }
}

#Preview {
    ProxyListView()
        .environmentObject(ProxyManager())
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
