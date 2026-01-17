import XCTest
@testable import Helium

final class ProxyTests: XCTestCase {
    
    // MARK: - Shadowsocks Parsing
    
    func testParseShadowsocksURL() throws {
        // Standard format: ss://BASE64(method:password)@host:port#name
        let url = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388#MyProxy"
        let proxy = try Proxy.parse(url)
        
        XCTAssertEqual(proxy.name, "MyProxy")
        XCTAssertEqual(proxy.type, .shadowsocks)
        XCTAssertEqual(proxy.host, "example.com")
        XCTAssertEqual(proxy.port, 8388)
    }
    
    func testParseShadowsocksWithoutName() throws {
        let url = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388"
        let proxy = try Proxy.parse(url)
        
        XCTAssertEqual(proxy.name, "Shadowsocks")
        XCTAssertEqual(proxy.type, .shadowsocks)
    }
    
    // MARK: - SOCKS5 Parsing
    
    func testParseSOCKS5URL() throws {
        let url = "socks5://user:pass@proxy.example.com:1080#MySocks"
        let proxy = try Proxy.parse(url)
        
        XCTAssertEqual(proxy.name, "MySocks")
        XCTAssertEqual(proxy.type, .socks5)
        XCTAssertEqual(proxy.host, "proxy.example.com")
        XCTAssertEqual(proxy.port, 1080)
        XCTAssertEqual(proxy.username, "user")
        XCTAssertEqual(proxy.password, "pass")
    }
    
    func testParseSOCKS5WithoutAuth() throws {
        let url = "socks5://proxy.example.com:1080"
        let proxy = try Proxy.parse(url)
        
        XCTAssertEqual(proxy.type, .socks5)
        XCTAssertNil(proxy.username)
        XCTAssertNil(proxy.password)
    }
    
    // MARK: - HTTP Parsing
    
    func testParseHTTPURL() throws {
        let url = "http://proxy.example.com:8080"
        let proxy = try Proxy.parse(url)
        
        XCTAssertEqual(proxy.type, .http)
        XCTAssertEqual(proxy.host, "proxy.example.com")
        XCTAssertEqual(proxy.port, 8080)
    }
    
    // MARK: - Error Cases
    
    func testParseUnsupportedProtocol() {
        let url = "ftp://example.com:21"
        
        XCTAssertThrowsError(try Proxy.parse(url)) { error in
            XCTAssertEqual(error as? ProxyParseError, .unsupportedProtocol)
        }
    }
    
    func testParseInvalidFormat() {
        let url = "socks5://invalid"
        
        XCTAssertThrowsError(try Proxy.parse(url))
    }
}

final class FingerprintTests: XCTestCase {
    
    func testRandomFingerprintGeneration() {
        let fp1 = FingerprintConfig.random()
        let fp2 = FingerprintConfig.random()
        
        // CPU cores should be valid options
        XCTAssertTrue([4, 8, 12, 16].contains(fp1.cpuCores))
        XCTAssertTrue([4, 8, 12, 16].contains(fp2.cpuCores))
        
        // Memory should be valid options
        XCTAssertTrue([4, 8, 16].contains(fp1.deviceMemory))
        XCTAssertTrue([4, 8, 16].contains(fp2.deviceMemory))
        
        // Screen dimensions should be reasonable
        XCTAssertGreaterThan(fp1.screenWidth, 0)
        XCTAssertGreaterThan(fp1.screenHeight, 0)
        
        // Canvas noise should be in valid range
        XCTAssertGreaterThan(fp1.canvasNoise, 0)
        XCTAssertLessThan(fp1.canvasNoise, 0.01)
    }
    
    func testFingerprintDefaults() {
        let fp = FingerprintConfig()
        
        XCTAssertEqual(fp.cpuCores, 8)
        XCTAssertEqual(fp.deviceMemory, 8)
        XCTAssertEqual(fp.colorDepth, 24)
        XCTAssertEqual(fp.webrtcPolicy, .disableNonProxiedUdp)
    }
}

final class ProfileTests: XCTestCase {
    
    func testProfileCreation() {
        let profile = Profile(name: "Test Profile")
        
        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertEqual(profile.status, .ready)
        XCTAssertEqual(profile.launchCount, 0)
        XCTAssertNil(profile.proxyId)
        XCTAssertNil(profile.folderId)
        XCTAssertTrue(profile.tagIds.isEmpty)
    }
    
    func testProfileWithProxy() {
        let proxyId = UUID()
        let profile = Profile(name: "Proxied Profile", proxyId: proxyId)
        
        XCTAssertEqual(profile.proxyId, proxyId)
    }
    
    func testProfileWithFolder() {
        let folderId = UUID()
        let profile = Profile(name: "Organized Profile", folderId: folderId)
        
        XCTAssertEqual(profile.folderId, folderId)
    }
}

final class TagTests: XCTestCase {
    
    func testTagCreation() {
        let tag = Tag(name: "Work", color: .blue)
        
        XCTAssertEqual(tag.name, "Work")
        XCTAssertEqual(tag.color, .blue)
    }
    
    func testTagColors() {
        let allColors = TagColor.allCases
        
        XCTAssertTrue(allColors.contains(.red))
        XCTAssertTrue(allColors.contains(.blue))
        XCTAssertTrue(allColors.contains(.green))
    }
}

final class FolderTests: XCTestCase {
    
    func testFolderCreation() {
        let folder = Folder(name: "Projects")
        
        XCTAssertEqual(folder.name, "Projects")
        XCTAssertEqual(folder.icon, "folder.fill")
        XCTAssertNil(folder.parentId)
    }
    
    func testNestedFolder() {
        let parentId = UUID()
        let folder = Folder(name: "Subfolder", parentId: parentId)
        
        XCTAssertEqual(folder.parentId, parentId)
    }
}
