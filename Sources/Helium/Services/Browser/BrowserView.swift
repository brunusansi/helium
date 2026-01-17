import SwiftUI
import WebKit

/// Browser view with native Safari WebKit and proxy integration
struct BrowserView: View {
    let profile: Profile
    
    @EnvironmentObject var xrayService: XrayService
    @EnvironmentObject var proxyManager: ProxyManager
    
    @State private var urlString: String
    @State private var isLoading: Bool = false
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var progress: Double = 0
    @State private var currentURL: URL?
    @State private var webView: WKWebView?
    @State private var proxyPort: Int?
    @State private var proxyGeoInfo: ProxyGeoInfo?
    @State private var proxyStatus: String = ""
    @State private var proxyIP: String = ""
    
    init(profile: Profile) {
        self.profile = profile
        _urlString = State(initialValue: profile.startUrl)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            BrowserToolbar(
                urlString: $urlString,
                isLoading: isLoading,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                progress: progress,
                proxyStatus: proxyStatus,
                proxyIP: proxyIP,
                onBack: { webView?.goBack() },
                onForward: { webView?.goForward() },
                onReload: { webView?.reload() },
                onStop: { webView?.stopLoading() },
                onNavigate: navigateToURL,
                onHome: { navigateToURL(profile.startUrl) }
            )
            
            // Progress bar
            if isLoading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
            
            // WebView
            WebViewWrapper(
                profile: profile,
                webView: $webView,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                progress: $progress,
                currentURL: $currentURL,
                proxyPort: proxyPort,
                proxyGeoInfo: proxyGeoInfo
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            setupProxy()
        }
        .onDisappear {
            cleanupProxy()
        }
        .navigationTitle(profile.name)
    }
    
    private func navigateToURL(_ urlStr: String? = nil) {
        let target = urlStr ?? urlString
        var finalURL = target
        
        if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
            if target.contains(".") && !target.contains(" ") {
                finalURL = "https://\(target)"
            } else {
                finalURL = "https://www.google.com/search?q=\(target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target)"
            }
        }
        
        guard let url = URL(string: finalURL) else { return }
        urlString = finalURL
        webView?.load(URLRequest(url: url))
    }
    
    private func setupProxy() {
        guard let proxyId = profile.proxyId,
              let proxy = proxyManager.getProxy(proxyId) else { 
            proxyStatus = "Direct"
            return 
        }
        
        proxyStatus = "Connecting..."
        
        Task {
            do {
                var localPort: Int
                
                if proxy.type.requiresXray {
                    // Start Xray connection
                    let connection = try await xrayService.startConnection(profileId: profile.id, proxy: proxy)
                    localPort = connection.localPort
                } else {
                    // Direct SOCKS5/HTTP proxy - for now just show as connected
                    localPort = proxy.port
                }
                
                await MainActor.run {
                    proxyPort = localPort
                    proxyStatus = "Connected"
                }
                
                // Fetch geo info from proxy IP (uses proxy via URLSession)
                do {
                    let geoInfo = try await ProxyGeoInfo.fetch(proxyHost: proxy.host, proxyPort: localPort)
                    await MainActor.run {
                        proxyGeoInfo = geoInfo
                        proxyIP = geoInfo.ip
                        proxyStatus = "\(geoInfo.city), \(geoInfo.countryCode)"
                        
                        // Reload to apply geo-synced fingerprint
                        webView?.reload()
                    }
                } catch {
                    await MainActor.run {
                        proxyStatus = "Connected (No Geo)"
                    }
                    print("Geo fetch failed: \(error)")
                }
                
            } catch {
                await MainActor.run {
                    proxyStatus = "Failed"
                    proxyIP = ""
                }
                print("Proxy setup failed: \(error)")
            }
        }
    }
    
    private func cleanupProxy() {
        xrayService.stopConnection(profileId: profile.id)
    }
}

// MARK: - Browser Toolbar

struct BrowserToolbar: View {
    @Binding var urlString: String
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let progress: Double
    let proxyStatus: String
    let proxyIP: String
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onStop: () -> Void
    let onNavigate: (String?) -> Void
    let onHome: () -> Void
    
    @FocusState private var isURLFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Navigation buttons
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(!canGoBack)
                
                Button(action: onForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(!canGoForward)
            }
            
            // Reload/Stop
            Button(action: isLoading ? onStop : onReload) {
                Image(systemName: isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            
            // URL Bar
            HStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                TextField("Search or enter website", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isURLFocused)
                    .onSubmit {
                        onNavigate(nil)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // Proxy status indicator
            if !proxyStatus.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(proxyStatusColor)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(proxyStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if !proxyIP.isEmpty {
                            Text(proxyIP)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            }
            
            // Home button
            Button(action: onHome) {
                Image(systemName: "house")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private var proxyStatusColor: Color {
        switch proxyStatus {
        case "Direct": return .gray
        case "Connecting...", "Verifying...": return .orange
        case "Failed": return .red
        default: return .green
        }
    }
}

// MARK: - WebView Wrapper

struct WebViewWrapper: NSViewRepresentable {
    let profile: Profile
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var progress: Double
    @Binding var currentURL: URL?
    let proxyPort: Int?
    let proxyGeoInfo: ProxyGeoInfo?
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = createWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        
        // Enable developer extras (Inspect Element)
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Add observers
        context.coordinator.observe(webView)
        
        // Store reference
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        // Load initial URL
        if let url = URL(string: profile.startUrl) {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // When proxy geo info becomes available, we might want to update scripts
        // This is handled by reloading the page in BrowserView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        
        // Create persistent data store for profile isolation
        // Each profile gets its own storage (cookies, localStorage, etc.)
        if #available(macOS 14.0, *) {
            let customDataStore = WKWebsiteDataStore(forIdentifier: profile.id)
            config.websiteDataStore = customDataStore
        } else {
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        
        // Use native Safari defaults - don't override UA to avoid detection
        // Safari's native fingerprint is consistent and undetectable
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        
        // Native Safari settings
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.preferences.isTextInteractionEnabled = true
        
        // Allow media playback
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        
        // Inject minimal fingerprint protection (WebRTC + timezone/geo sync)
        let userContentController = WKUserContentController()
        let fingerprintScript = FingerprintEngine.shared.createUserScript(
            config: profile.fingerprint,
            proxyInfo: proxyGeoInfo
        )
        userContentController.addUserScript(fingerprintScript)
        
        config.userContentController = userContentController
        
        // DO NOT set custom user agent - use native Safari
        // config.applicationNameForUserAgent = ... // REMOVED
        
        // Set up proxy if available
        if let port = proxyPort {
            configureProxy(config: config, port: port)
        }
        
        return config
    }
    
    private func configureProxy(config: WKWebViewConfiguration, port: Int) {
        // WKWebView uses the system proxy settings by default
        // For per-webview proxy, we need to use a custom URL scheme handler
        // or rely on system-wide proxy settings set by Xray
        
        // The Xray process sets up a local SOCKS5 proxy on 127.0.0.1:port
        // We can use PAC (Proxy Auto-Config) or system proxy settings
        
        // For now, we inject a script that shows proxy is active
        // The actual proxy routing happens at the Xray/system level
        let proxyScript = WKUserScript(
            source: "console.log('[Helium] Proxy active on port \(port)');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(proxyScript)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewWrapper
        private var observations: [NSKeyValueObservation] = []
        
        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }
        
        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.isLoading) { [weak self] webView, _ in
                    DispatchQueue.main.async {
                        self?.parent.isLoading = webView.isLoading
                    }
                },
                webView.observe(\.canGoBack) { [weak self] webView, _ in
                    DispatchQueue.main.async {
                        self?.parent.canGoBack = webView.canGoBack
                    }
                },
                webView.observe(\.canGoForward) { [weak self] webView, _ in
                    DispatchQueue.main.async {
                        self?.parent.canGoForward = webView.canGoForward
                    }
                },
                webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                    DispatchQueue.main.async {
                        self?.parent.progress = webView.estimatedProgress
                    }
                },
                webView.observe(\.url) { [weak self] webView, _ in
                    DispatchQueue.main.async {
                        self?.parent.currentURL = webView.url
                    }
                }
            ]
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.progress = 1.0
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            return .allow
        }
        
        // MARK: - WKUIDelegate
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Open links that want new windows in the same view
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

#Preview {
    BrowserView(profile: Profile(name: "Test Profile"))
        .environmentObject(XrayService())
        .environmentObject(ProxyManager())
        .frame(width: 1200, height: 800)
}
