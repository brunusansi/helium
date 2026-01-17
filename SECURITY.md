# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in Helium, please report it responsibly.

### How to Report

1. **DO NOT** open a public GitHub issue for security vulnerabilities
2. Email us at: **security@helium.app** (or create a private security advisory)
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt within 48 hours
- **Assessment**: We will assess the vulnerability within 7 days
- **Fix Timeline**: Critical vulnerabilities will be addressed within 30 days
- **Disclosure**: We will coordinate with you on public disclosure timing

### Security Measures in Helium

Helium implements several security measures:

1. **Profile Isolation**: Each browser profile is completely isolated with separate data stores
2. **WebRTC Protection**: Prevents real IP leaks through WebRTC
3. **Local-Only Data**: All profile data is stored locally, never uploaded
4. **No Telemetry**: Helium does not collect any usage data
5. **Open Source**: Full transparency through open source code

### Scope

The following are in scope for security reports:

- Fingerprint leaks that could identify users
- Profile data exposure between profiles
- WebRTC/IP leaks
- Proxy credential exposure
- Local privilege escalation
- Remote code execution

### Out of Scope

- Social engineering attacks
- Physical attacks requiring device access
- Denial of service attacks
- Issues in dependencies (report to upstream)

## Security Best Practices for Users

1. **Keep Updated**: Always use the latest version of Helium
2. **Use Strong Proxies**: Choose reputable proxy providers
3. **Regular Profile Rotation**: Create new profiles periodically
4. **Check for Leaks**: Use sites like browserleaks.com to verify protection
5. **Secure Your System**: Keep macOS and Xcode updated

## Acknowledgments

We appreciate security researchers who help keep Helium secure. Contributors will be acknowledged in our security hall of fame (with permission).

---

Thank you for helping keep Helium and its users safe! 🛡️
