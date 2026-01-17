# Contributing to Helium

Thank you for your interest in contributing to Helium! This document provides guidelines and information for contributors.

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9 or later
- Git

### Setting Up the Development Environment

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/helium.git
   cd helium
   ```

2. **Build the project**
   ```bash
   swift build
   ```

3. **Run tests**
   ```bash
   swift test
   ```

4. **Open in Xcode (optional)**
   ```bash
   open Package.swift
   ```

## 📋 How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates.

When reporting a bug, include:
- macOS version
- Helium version
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots if applicable

### Suggesting Features

Feature requests are welcome! Please provide:
- Clear description of the feature
- Use case / problem it solves
- Possible implementation approach (optional)

### Pull Requests

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed

3. **Test your changes**
   ```bash
   swift test
   ```

4. **Commit with a descriptive message**
   ```bash
   git commit -m "Add: Description of your change"
   ```

5. **Push and create a Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```

## 🏗️ Project Structure

```
helium/
├── Sources/Helium/
│   ├── App/                 # Main app entry point
│   ├── Models/              # Data models (Profile, Proxy, Fingerprint)
│   ├── Views/               # SwiftUI views
│   │   ├── Components/      # Reusable UI components
│   │   ├── Profiles/        # Profile management views
│   │   ├── Proxies/         # Proxy management views
│   │   └── Settings/        # Settings views
│   ├── Services/            # Business logic
│   │   ├── Browser/         # WebKit browser integration
│   │   ├── Fingerprint/     # Fingerprint spoofing engine
│   │   └── Xray/            # Xray-core integration
│   └── Utilities/           # Helper functions
├── Tests/                   # Unit tests
├── Resources/               # Assets and resources
└── docs/                    # Documentation
```

## 🎨 Code Style

### Swift

- Use Swift's standard naming conventions
- Prefer `let` over `var` when possible
- Use `guard` for early returns
- Add documentation comments for public APIs
- Keep functions small and focused

### SwiftUI

- Use view composition over large views
- Extract reusable components
- Use `@StateObject` for view-owned objects
- Use `@EnvironmentObject` for shared state

### Example

```swift
/// A view that displays a single profile card
struct ProfileCard: View {
    let profile: Profile
    let onLaunch: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            proxyInfo
            actionButtons
        }
        .padding()
        .background(cardBackground)
    }
    
    private var headerSection: some View {
        HStack {
            Text(profile.name)
                .font(.headline)
            Spacer()
            StatusBadge(status: profile.status)
        }
    }
    
    // ... more computed properties
}
```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter ProfileTests
```

### Writing Tests

- Place tests in `Tests/HeliumTests/`
- Name test files with `*Tests.swift` suffix
- Test both success and failure cases

```swift
import XCTest
@testable import Helium

final class ProxyParserTests: XCTestCase {
    func testParseShadowsocksURL() throws {
        let url = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@server:8388#MyProxy"
        let proxy = try Proxy.parse(url)
        
        XCTAssertEqual(proxy.name, "MyProxy")
        XCTAssertEqual(proxy.type, .shadowsocks)
        XCTAssertEqual(proxy.host, "server")
        XCTAssertEqual(proxy.port, 8388)
    }
}
```

## 📝 Commit Messages

Use conventional commit format:

- `Add:` New feature
- `Fix:` Bug fix
- `Update:` Update existing feature
- `Refactor:` Code refactoring
- `Docs:` Documentation changes
- `Test:` Test additions/changes
- `Chore:` Build/tooling changes

Examples:
```
Add: VMess protocol support in proxy parser
Fix: WebRTC leak when using SOCKS5 proxy
Update: Improve fingerprint randomization
Docs: Add contribution guidelines
```

## 🔒 Security

If you discover a security vulnerability, please **DO NOT** open a public issue. Instead, email security@helium.app (or create a private security advisory on GitHub).

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

## 💬 Questions?

- Open a [Discussion](https://github.com/brunusansi/helium/discussions)
- Check existing [Issues](https://github.com/brunusansi/helium/issues)

Thank you for contributing to Helium! 🎉
