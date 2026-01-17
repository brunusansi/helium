import Foundation
import CryptoKit

/// Service for exporting and importing profiles with encryption
final class ProfileExporter {
    
    // MARK: - Export
    
    /// Export profiles to an encrypted JSON file
    /// - Parameters:
    ///   - profiles: Array of profiles to export
    ///   - password: Password for encryption (optional, if nil exports unencrypted)
    ///   - includeProxies: Whether to include associated proxy configurations
    /// - Returns: Data containing the exported profile bundle
    static func exportProfiles(
        _ profiles: [Profile],
        password: String? = nil,
        includeProxies: Bool = false,
        proxies: [Proxy] = []
    ) throws -> Data {
        // Create export bundle
        let bundle = ProfileExportBundle(
            version: "1.0",
            exportDate: Date(),
            profiles: profiles,
            proxies: includeProxies ? proxies.filter { proxy in
                profiles.contains { $0.proxyId == proxy.id }
            } : [],
            isEncrypted: password != nil
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        var jsonData = try encoder.encode(bundle)
        
        // Encrypt if password provided
        if let password = password {
            let encryptedData = try encrypt(data: jsonData, password: password)
            
            // Wrap in encrypted container
            let container = EncryptedContainer(
                version: "1.0",
                algorithm: "ChaChaPoly",
                data: encryptedData.base64EncodedString()
            )
            jsonData = try encoder.encode(container)
        }
        
        return jsonData
    }
    
    /// Export profiles to a file URL
    static func exportProfilesToFile(
        _ profiles: [Profile],
        to url: URL,
        password: String? = nil,
        includeProxies: Bool = false,
        proxies: [Proxy] = []
    ) throws {
        let data = try exportProfiles(
            profiles,
            password: password,
            includeProxies: includeProxies,
            proxies: proxies
        )
        try data.write(to: url)
    }
    
    // MARK: - Import
    
    /// Import profiles from encrypted JSON data
    /// - Parameters:
    ///   - data: Exported profile data
    ///   - password: Password for decryption (if encrypted)
    /// - Returns: Import result with profiles and proxies
    static func importProfiles(
        from data: Data,
        password: String? = nil
    ) throws -> ProfileImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Check if encrypted
        if let container = try? decoder.decode(EncryptedContainer.self, from: data) {
            guard let password = password else {
                throw ProfileExportError.passwordRequired
            }
            
            guard let encryptedData = Data(base64Encoded: container.data) else {
                throw ProfileExportError.invalidData
            }
            
            let decryptedData = try decrypt(data: encryptedData, password: password)
            let bundle = try decoder.decode(ProfileExportBundle.self, from: decryptedData)
            
            return ProfileImportResult(
                profiles: bundle.profiles,
                proxies: bundle.proxies,
                wasEncrypted: true,
                exportDate: bundle.exportDate
            )
        } else {
            // Unencrypted
            let bundle = try decoder.decode(ProfileExportBundle.self, from: data)
            
            return ProfileImportResult(
                profiles: bundle.profiles,
                proxies: bundle.proxies,
                wasEncrypted: false,
                exportDate: bundle.exportDate
            )
        }
    }
    
    /// Import profiles from a file URL
    static func importProfilesFromFile(
        at url: URL,
        password: String? = nil
    ) throws -> ProfileImportResult {
        let data = try Data(contentsOf: url)
        return try importProfiles(from: data, password: password)
    }
    
    // MARK: - Encryption
    
    private static func deriveKey(from password: String, salt: Data) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        
        // Use HKDF for key derivation
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passwordData),
            salt: salt,
            info: Data("Helium Profile Export".utf8),
            outputByteCount: 32
        )
        
        return key
    }
    
    private static func encrypt(data: Data, password: String) throws -> Data {
        // Generate random salt
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        
        let key = deriveKey(from: password, salt: salt)
        
        let sealedBox = try ChaChaPoly.seal(data, using: key)
        
        // Combine salt + nonce + ciphertext + tag
        var result = salt
        result.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)
        
        return result
    }
    
    private static func decrypt(data: Data, password: String) throws -> Data {
        guard data.count > 16 + 12 + 16 else { // salt + nonce + tag minimum
            throw ProfileExportError.invalidData
        }
        
        // Extract components
        let salt = data.prefix(16)
        let nonce = data.dropFirst(16).prefix(12)
        let ciphertext = data.dropFirst(28).dropLast(16)
        let tag = data.suffix(16)
        
        let key = deriveKey(from: password, salt: salt)
        
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        
        return try ChaChaPoly.open(sealedBox, using: key)
    }
}

// MARK: - Data Structures

struct ProfileExportBundle: Codable {
    let version: String
    let exportDate: Date
    let profiles: [Profile]
    let proxies: [Proxy]
    let isEncrypted: Bool
}

struct EncryptedContainer: Codable {
    let version: String
    let algorithm: String
    let data: String
}

struct ProfileImportResult {
    let profiles: [Profile]
    let proxies: [Proxy]
    let wasEncrypted: Bool
    let exportDate: Date
}

// MARK: - Errors

enum ProfileExportError: LocalizedError {
    case passwordRequired
    case invalidPassword
    case invalidData
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "This file is encrypted. Please provide a password."
        case .invalidPassword:
            return "Invalid password. Could not decrypt the file."
        case .invalidData:
            return "The file is corrupted or in an unsupported format."
        case .encryptionFailed:
            return "Failed to encrypt the profile data."
        case .decryptionFailed:
            return "Failed to decrypt the profile data."
        }
    }
}
