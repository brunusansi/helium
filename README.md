<div align="center">

# <img src="docs/assets/helium-icon.png" width="40" height="40" alt="Helium"> Helium

### The Open Source Anti-Detect Browser

**A powerful anti-detect browser that puts you in control of your browsing experience.**

[![macOS](https://img.shields.io/badge/macOS-Intel%20%7C%20Apple%20Silicon-blue?logo=apple)](https://github.com/brunusansi/helium/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/brunusansi/helium?style=social)](https://github.com/brunusansi/helium)

[**Download**](https://github.com/brunusansi/helium/releases) · [**Documentation**](docs/)

<img src="docs/assets/screenshot.png" width="800" alt="Helium Screenshot">

</div>

---

## ✨ Features

### 🎭 Advanced Fingerprint Isolation

Helium leverages Safari's **Advanced Privacy Protection** combined with custom fingerprint spoofing to create unique, undetectable browser profiles.

| Feature | Description |
|---------|-------------|
| **Hardware Randomization** | CPU cores (4/8/12/16), Device Memory (4/8/16 GB), GPU renderer |
| **Timezone & Geo Spoofing** | Auto-match proxy IP location or choose from 50+ cities |
| **Language Spoofing** | 60+ languages with full browser locale, HTTP headers, and i18n API modification |
| **WebRTC Protection** | Forces `disable_non_proxied_udp` policy to prevent real IP leaks |
| **Canvas Fingerprint** | Unique noise injection per profile |
| **WebGL Fingerprint** | Randomized renderer and vendor strings |
| **Audio Fingerprint** | Per-profile audio context noise |
| **Font Fingerprint** | Controlled font enumeration |

### 🔗 Powerful Network Engine (Xray-core)

Built-in integration with [Xray-core](https://github.com/XTLS/Xray-core) for advanced proxy support.

**Supported Protocols:**
- ✅ **VMess** / **VLESS** (with REALITY)
- ✅ **Trojan**
- ✅ **Shadowsocks** (including 2022 cipher) - `ss://` links
- ✅ **SOCKS5** / **HTTP**

**Advanced Transports:**
- REALITY, XHTTP, gRPC, mKCP, WebSocket, HTTP/2

**Smart Features:**
- 🔄 **Proxy Chain (Pre-Proxy)**: `[Local]` → `[Pre-Proxy]` → `[Target Node]` → `[Web]`
- 🌐 **Smart Routing**: Automatic IPv4/IPv6 dual-stack handling
- 📋 **URL Import**: Paste `ss://`, `vmess://`, `vless://`, `trojan://` links directly

### 📁 Profile Management

Create unlimited isolated browser profiles, each with its own:

- 🍪 Cookies, localStorage, IndexedDB
- 🔧 Extensions and settings
- 🌐 Proxy configuration
- 🎭 Unique fingerprint
- 🏷️ Tags and folder organization

### 🎨 Beautiful Minimalist Interface

- Native macOS design with SwiftUI
- Smooth animations and transitions
- Dark/Light mode support
- Keyboard shortcuts for power users
- Drag & drop profile organization

---

## 🎯 Use Cases

| Industry | Applications |
|----------|--------------|
| **E-commerce** | Multi-account management for Amazon, eBay, Shopify sellers |
| **Affiliate Marketing** | Gmail, social media account farming |
| **Social Media** | Facebook, TikTok, YouTube, LinkedIn multi-account |
| **Bounty & Airdrop** | Crypto airdrops, referral programs |
| **Ticket Resale** | Multi-account ticket purchasing |
| **Web Scraping** | Rotate fingerprints to avoid detection |
| **Privacy & Anonymity** | Protect your digital identity |
| **Cloud Providers** | Advanced bypass for Azure, GCP, AWS, Linode, Akamai |

---

## 🚀 Quick Start

### Installation

**Download the latest release:**

```bash
# Using Homebrew (coming soon)
brew install --cask helium

# Or download directly from releases
# https://github.com/brunusansi/helium/releases
```

### Create Your First Profile

1. **Launch Helium**
2. Click **+ New Profile**
3. Configure fingerprint settings (or use Auto)
4. Assign a proxy (optional)
5. Click **Launch** 🚀

### Import Proxies

Helium supports multiple proxy formats:

```
# Shadowsocks
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@server:8388#MyProxy

# SOCKS5
socks5://user:pass@server:1080

# VMess (JSON or base64)
vmess://eyJ2IjoiMiIsInBzIjoiTXlWTWVzcyIsImFkZCI6InNlcnZlciIsInBvcnQiOiI0NDMiLCJ0eXBlIjoibm9uZSIsImlkIjoiYWJjZC0xMjM0IiwiYWlkIjoiMCIsIm5ldCI6IndzIiwicGF0aCI6Ii9wYXRoIiwiaG9zdCI6Imhvc3QiLCJ0bHMiOiJ0bHMifQ==

# VLESS
vless://uuid@server:443?encryption=none&type=ws&host=host&path=/path#Name

# Trojan
trojan://password@server:443?sni=host#Name
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Helium Application                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   SwiftUI   │  │   Profile   │  │   Fingerprint       │  │
│  │   Interface │  │   Manager   │  │   Engine            │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Safari WebKit Engine                        ││
│  │         (Advanced Privacy Protection + WKWebView)        ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Xray-core Network Engine                    ││
│  │    VMess | VLESS | Trojan | Shadowsocks | SOCKS5 | HTTP  ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Building from Source

### Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.9+

### Build

```bash
# Clone the repository
git clone https://github.com/brunusansi/helium.git
cd helium

# Build with Swift Package Manager
swift build -c release

# Or open in Xcode
open Helium.xcodeproj
```

### Run Tests

```bash
swift test
```

---

## 📊 Fingerprint Detection Status

Helium is tested against major anti-fraud and bot detection systems:

| Platform | Status | Notes |
|----------|--------|-------|
| **Cloudflare** | ✅ Bypass | Full bypass including Turnstile |
| **DataDome** | ✅ Bypass | Requires proper fingerprint config |
| **PerimeterX** | ✅ Bypass | WebGL/Canvas noise required |
| **Kasada** | ✅ Bypass | Audio fingerprint noise helps |
| **Akamai** | ✅ Bypass | Full protocol support |
| **Google** | ✅ Bypass | Multi-account safe |
| **Facebook** | ✅ Bypass | Tested with warm-up |
| **Amazon** | ✅ Bypass | E-commerce ready |
| **CreepJS** | ✅ Pass | Unique fingerprints per profile |
| **BrowserLeaks** | ✅ Pass | No leaks detected |

---

## 🆚 Comparison with Commercial Solutions

| Feature | Helium | Multilogin | GoLogin | Dolphin Anty |
|---------|--------|------------|---------|--------------|
| **Price** | 🆓 Free | $99+/mo | $49+/mo | $89+/mo |
| **Open Source** | ✅ | ❌ | ❌ | ❌ |
| **Unlimited Profiles** | ✅ | ❌ | ❌ | ❌ |
| **Safari Engine** | ✅ | ❌ | ❌ | ❌ |
| **Built-in Xray-core** | ✅ | ❌ | ❌ | ❌ |
| **macOS Native** | ✅ | ⚠️ Electron | ⚠️ Electron | ⚠️ Electron |
| **Privacy** | Local only | Cloud | Cloud | Cloud |

---

## 🗺️ Roadmap

- [x] Core profile management
- [x] Xray-core integration
- [x] Basic fingerprint spoofing
- [ ] Profile sync (encrypted, optional)
- [ ] Browser automation API
- [ ] Selenium/Playwright integration
- [ ] Mobile user-agent emulation
- [ ] Team collaboration features
- [ ] Windows & Linux support

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

```bash
# Fork the repository
# Create your feature branch
git checkout -b feature/amazing-feature

# Commit your changes
git commit -m 'Add amazing feature'

# Push to the branch
git push origin feature/amazing-feature

# Open a Pull Request
```

---

## 📄 License

Helium is open source software licensed under the [MIT License](LICENSE).

---

## ⚠️ Disclaimer

Helium is designed for legitimate privacy protection, web development testing, and authorized multi-account management. Users are responsible for ensuring their use complies with applicable laws and terms of service. The developers do not condone or support any illegal activities.

---

<div align="center">

**Built with ❤️ for the privacy-conscious community**

[⬆ Back to top](#helium)

</div>
