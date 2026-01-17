import SwiftUI
import WebKit
@preconcurrency import SafariServices

/// Browser view with WebKit and fingerprint injection
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
                proxyPort: proxyPort
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
              let proxy = proxyManager.getProxy(proxyId) else { return }
        
        if proxy.type.requiresXray {
            Task {
                do {
                    let connection = try await xrayService.startConnection(profileId: profile.id, proxy: proxy)
                    proxyPort = connection.localPort
                } catch {
                    print("Failed to start proxy: \(error)")
                }
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
        // Updates handled via Coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        
        // Create separate persistent data store for profile isolation
        // Each profile gets its own data store identified by profile ID
        let dataStoreID = profile.id
        
        // Use persistent data store for better cookie/session handling
        if #available(macOS 14.0, *) {
            // macOS 14+ supports custom persistent data stores
            let customDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
            config.websiteDataStore = customDataStore
        } else {
            // Fallback to non-persistent for older macOS
            config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        
        // Modern WebKit preferences
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        
        // Enable modern features
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.preferences.isTextInteractionEnabled = true
        
        // Allow media playback
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        
        // Inject fingerprint protection script
        let userContentController = WKUserContentController()
        let fingerprintScript = FingerprintEngine.shared.createUserScript(config: profile.fingerprint)
        userContentController.addUserScript(fingerprintScript)
        
        // Add proxy configuration script if proxy is active
        if let port = proxyPort {
            let proxyScript = createProxyScript(port: port)
            userContentController.addUserScript(proxyScript)
        }
        
        config.userContentController = userContentController
        
        // Set custom user agent if specified, otherwise use modern Safari UA
        if let customUA = profile.userAgent {
            config.applicationNameForUserAgent = customUA
        } else {
            // Use latest Safari user agent
            config.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        }
        
        // Enable advanced features
        config.limitsNavigationsToAppBoundDomains = false
        
        return config
    }
    
    private func createProxyScript(port: Int) -> WKUserScript {
        // Note: WebKit doesn't support per-request proxy via JS
        // The proxy is handled at the system/XrayService level
        let script = """
        // Proxy configured via system - port \(port)
        console.log('[Helium] Proxy active on port \(port)');
        """
        return WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
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
            // Allow all navigation
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
