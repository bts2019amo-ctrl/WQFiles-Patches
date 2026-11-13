import Foundation
import SwiftUI
import UIKit
import Security
import CryptoKit

private struct IOSKeyResponseEnvelope: Decodable { let result: IOSKeyResponseResult }
private struct IOSKeyResponseResult: Decodable { let data: IOSKeyResponseData }
private struct IOSKeyResponseData: Decodable { let json: IOSKeyValidation }
private struct IOSKeyValidation: Decodable {
    let success: Bool?; let valid: Bool?; let active: Bool?; let status: String?
    let errorCode: String?; let message: String?; let reason: String?; let expiresAt: String?
}

@MainActor
final class IOSKeySession: ObservableObject {
    private(set) static var runtimeAuthorized = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isChecking = false
    @Published private(set) var expiresAt: Date?
    @Published var errorMessage: String?

    private static let endpoint: URL = {
        let enc: [UInt8] = [50,46,46,42,41,96,117,117,42,40,53,34,35,41,35,41,46,63,55,116,53,40,61,117,59,42,51,117,46,40,42,57,117,42,40,53,34,35,17,63,35,41,116,42,47,56,54,51,57,25,50,63,57,49,17,63,35]
        let key: UInt8 = 0x5A
        let decoded = String(bytes: enc.map { $0 ^ key }, encoding: .utf8) ?? "https://proxysystem.org/api/trpc/proxyKeys.publicCheckKey"
        return URL(string: decoded)!
    }()

    private static let keychainService = "com.3105.ios-key"
    private static let keychainAccount = "proxy-system-key"
    private static let deviceBindingKeychainService = "com.3105.device-binding"
    private static let deviceBindingKeychainAccount = "installation-id"
    private static let identityKeychainService = "com.3105.installation-integrity"
    private static let identityKeychainAccount = "bundle-fingerprint"
    /// Original package id from Info.plist — changing this kills the app
    private static let expectedBundleIdentifier = Bundle.main.bundleIdentifier ?? ""
    private var storedKey: String?
    private var monitorTask: Task<Void, Never>?
    private var didPassCalculatorGate = false

    init() {
        storedKey = Self.readKeychain()
        Self.enforceInstallationIdentity()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                if AD_isTampered() != 0 {
                    log("integrity: periodic runtime tamper")
                    await MainActor.run {
                        self?.logout()
                        self?.errorMessage = "Ambiente comprometido detectado."
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    AD_killProcess()
                    return
                }
                await MainActor.run { Self.enforceInstallationIdentity() }
                await self?.refresh()
            }
        }
    }

    deinit { monitorTask?.cancel() }

    func passCalculatorGate() {
        guard !didPassCalculatorGate else { return }
        didPassCalculatorGate = true
        if storedKey != nil { Task { await refresh() } }
    }

    func submit(_ rawKey: String) {
        guard didPassCalculatorGate else { return }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { errorMessage = "Digite sua chave iOS."; return }
        Task { await validate(key, saveOnSuccess: true) }
    }

    func refresh() async {
        guard didPassCalculatorGate, !isChecking, let storedKey, !storedKey.isEmpty else { return }
        await validate(storedKey, saveOnSuccess: false)
    }

    func logout() {
        try? PatchProjectLibrary.resetAll()
        PatchKeyStore.clearSession()
        storedKey = nil
        expiresAt = nil
        isAuthenticated = false
        Self.runtimeAuthorized = false
        errorMessage = nil
        Self.deleteKeychain()
    }

    func validateIntegrityOnForeground() {
        if AD_isTampered() != 0 {
            log("integrity: runtime tamper on foreground")
            logout()
            errorMessage = "Ambiente comprometido detectado."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { AD_killProcess() }
            return
        }
        Self.enforceInstallationIdentity()
        if !Self.runtimeAuthorized { isAuthenticated = false }
    }

    private func validate(_ key: String, saveOnSuccess: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            let input: [String: Any] = ["json": ["key": key, "deviceId": try Self.deviceIdentifier()]]
            let data = try JSONSerialization.data(withJSONObject: input)
            components.queryItems = [URLQueryItem(name: "input", value: String(data: data, encoding: .utf8))]
            let (responseData, response) = try await URLSession.shared.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let envelope = try JSONDecoder().decode(IOSKeyResponseEnvelope.self, from: responseData)
            let result = envelope.result.data.json
            let accepted = result.success == true && result.active == true && result.status?.lowercased() == "active"
            guard accepted else {
                logout()
                if result.status?.lowercased() == "device_mismatch" || result.errorCode?.uppercased() == "DEVICE_MISMATCH" {
                    errorMessage = result.message ?? "Esta chave já está vinculada a outro aparelho."
                } else {
                    errorMessage = result.message ?? result.reason ?? "Chave inválida ou expirada."
                }
                return
            }
            storedKey = key
            if saveOnSuccess { Self.writeKeychain(key) }
            expiresAt = result.expiresAt.flatMap(Self.parseDate)
            errorMessage = nil
            Self.runtimeAuthorized = true
            isAuthenticated = true
        } catch {
            if !isAuthenticated { errorMessage = "Não foi possível verificar a chave. Verifique sua conexão." }
        }
    }

    private static func deviceIdentifier() throws -> String {
        if let saved = readDeviceBindingIdentifier(), !saved.isEmpty { return saved }
        let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard writeDeviceBindingIdentifier(generated) else { throw KeychainError.unableToPersistDeviceBinding }
        return generated
    }
    private enum KeychainError: Error { case unableToPersistDeviceBinding }

    private static func readDeviceBindingIdentifier() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: deviceBindingKeychainService, kSecAttrAccount as String: deviceBindingKeychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeDeviceBindingIdentifier(_ identifier: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: deviceBindingKeychainService, kSecAttrAccount as String: deviceBindingKeychainAccount]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(identifier.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Changing package id / CFBundleIdentifier is hard tamper → kill.
    /// Normal IPA update with same package id is allowed.
    private static func enforceInstallationIdentity() {
        let currentBundleID = Bundle.main.bundleIdentifier ?? ""

        if currentBundleID != expectedBundleIdentifier {
            log("integrity: PACKAGE ID CHANGED — expected \(expectedBundleIdentifier), got \(currentBundleID)")
            try? PatchProjectLibrary.resetAll()
            PatchKeyStore.deleteAll()
            deleteKeychain()
            runtimeAuthorized = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AD_killProcess()
            }
            return
        }

        let fingerprint = installationFingerprint
        let identityKey = "installation.identity.fingerprint"
        let previousDefaults = UserDefaults.standard.string(forKey: identityKey)
        let previousKeychain = readInstallationBaseline()
        let changed = (previousDefaults != nil && previousDefaults != fingerprint)
            || (previousKeychain != nil && previousKeychain != fingerprint)
            || (previousKeychain != nil && previousDefaults == nil)

        if changed {
            log("integrity: installation fingerprint changed (update or possible repackage)")
            try? PatchProjectLibrary.resetAll()
            PatchKeyStore.deleteAll()
            deleteKeychain()
            runtimeAuthorized = false
            if AD_isTampered() != 0 {
                log("integrity: fingerprint change + runtime tamper — killing")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AD_killProcess() }
                return
            }
        }
        UserDefaults.standard.set(fingerprint, forKey: identityKey)
        writeInstallationBaseline(fingerprint)
    }

    static var installationFingerprint: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "unknown"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let bundleHash = bundleDigest() ?? executableDigest() ?? "missing-bundle"
        return "\(bundleID)|3105|\(displayName)|version:\(version)|bundle:\(bundleHash)"
    }

    private static func executableDigest() -> String? {
        guard let url = Bundle.main.executableURL, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func bundleDigest() -> String? {
        let root = Bundle.main.bundleURL.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else { return nil }
        var digestInput = Data()
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }
            let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
            digestInput.append(contentsOf: Data(relativePath.utf8))
            digestInput.append(0)
            digestInput.append(contentsOf: data)
            digestInput.append(0)
        }
        return SHA256.hash(data: digestInput).map { String(format: "%02x", $0) }.joined()
    }

    private static func readInstallationBaseline() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: identityKeychainService, kSecAttrAccount as String: identityKeychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeInstallationBaseline(_ fingerprint: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: identityKeychainService, kSecAttrAccount as String: identityKeychainAccount]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(fingerprint.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
    }

    private static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
