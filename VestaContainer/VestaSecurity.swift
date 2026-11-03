//
//  VestaSecurity.swift
//
//  钥匙串保存授权和加密密钥。apps.json 用 AES-GCM。启动时用代码签名核对主程序和资源。
//

import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// 开发测试阶段临时放行。恢复正式的设备绑定和许可证校验时，把 enabled 改回 false。
nonisolated enum VestaDevelopmentAccess {
    static let enabled = true
}

nonisolated enum VestaKeychain {
    private static let service = "devplaceholder.MWTZW5AT.MyApp.vesta"

    private static func silentContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    static func load(account: String) -> Data? {
        if VestaDevelopmentAccess.enabled {
            return nil
        }
        let context = silentContext()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return nil
        }
        guard status == errSecSuccess else {
            print("[Keychain] 读取失败 \(account) status=\(status)")
            return nil
        }
        guard let data = item as? Data else {
            print("[Keychain] 读取到的不是数据：\(account)")
            return nil
        }
        return data
    }

    static func save(_ data: Data, account: String) -> Bool {
        if VestaDevelopmentAccess.enabled {
            return true
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let context = silentContext()
        var updateQuery = base
        updateQuery[kSecUseAuthenticationContext as String] = context
        let updated = SecItemUpdate(updateQuery as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess {
            return true
        }
        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        insert[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("[Keychain] 写入失败 \(account) status=\(status)")
            return false
        }
        return true
    }
}

nonisolated enum LibraryVault {
    private static let magic = Data("VST1".utf8)

    static func seal(_ plain: Data) -> Data? {
        guard let key = symmetricKey() else { return nil }
        do {
            let sealed = try AES.GCM.seal(plain, using: key)
            guard let combined = sealed.combined else {
                print("[Library] AES 封装失败")
                return nil
            }
            return magic + combined
        } catch {
            print("[Library] 加密失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 明文旧文件返回 `.legacy`。魔数对但解不开返回 nil，调用方不要覆盖原文件。
    static func open(_ data: Data) -> Data? {
        guard data.starts(with: magic) else {
            return data
        }
        guard let key = existingKey() else {
            print("[Library] 本地没有解密密钥，启动时不访问钥匙串弹窗")
            return nil
        }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
            return try AES.GCM.open(box, using: key)
        } catch {
            print("[Library] apps.json 解密失败：\(error.localizedDescription)")
            return nil
        }
    }

    static func isSealed(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    /// 启动时只读本地密钥文件。没有文件时才生成，不弹钥匙串。
    static func existingKey() -> SymmetricKey? {
        if let stored = readKeyFile(), stored.count == 32 {
            return SymmetricKey(data: stored)
        }
        if let stored = VestaKeychain.load(account: "library-aes"), stored.count == 32 {
            if writeKeyFile(stored) {
                return SymmetricKey(data: stored)
            }
        }
        return nil
    }

    private static func symmetricKey() -> SymmetricKey? {
        if let existing = existingKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        guard raw.count == 32, writeKeyFile(raw) else {
            print("[Library] 加密密钥没有写入本地文件")
            return nil
        }
        return key
    }

    private static var keyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/library.key")
    }

    private static func readKeyFile() -> Data? {
        try? Data(contentsOf: keyFile)
    }

    private static func writeKeyFile(_ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: keyFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
            return true
        } catch {
            print("[Library] 写入密钥失败：\(error.localizedDescription)")
            return false
        }
    }
}

/// 后台启动路径读取。授权变化时由 LicenseManager 更新。
nonisolated final class LicenseGate: @unchecked Sendable {
    static let shared = LicenseGate()

    private let lock = NSLock()
    private var advanced = false

    func setAdvanced(_ allowed: Bool) {
        lock.lock()
        advanced = allowed
        lock.unlock()
    }

    func allowsAdvanced() -> Bool {
        if VestaDevelopmentAccess.enabled {
            return true
        }
        lock.lock()
        defer { lock.unlock() }
        return advanced
    }
}

struct LicenseRecord: Codable {
    var key: String
    var activated: Bool
    var trialStart: Date

    private static let account = "license"
    private static let trialLength = 14
    private static let trialStartKey = "MyApp.trialStart"
    private static let activatedKey = "MyApp.licenseActivated"
    private static let savedLicenseKey = "MyApp.licenseKey"

    var trialDaysRemaining: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        return max(0, Self.trialLength - elapsed)
    }

    var allowsAdvanced: Bool {
        activated || trialDaysRemaining > 0
    }

    static func load() -> LicenseRecord {
        if let data = try? Data(contentsOf: fileURL),
           let record = try? JSONDecoder().decode(LicenseRecord.self, from: data) {
            return record
        }
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: trialStartKey) as? Date ?? Date()
        let record = LicenseRecord(
            key: defaults.string(forKey: savedLicenseKey) ?? "",
            activated: defaults.bool(forKey: activatedKey),
            trialStart: start
        )
        if record.save() {
            defaults.removeObject(forKey: activatedKey)
            defaults.removeObject(forKey: savedLicenseKey)
            defaults.removeObject(forKey: trialStartKey)
        }
        return record
    }

    func save() -> Bool {
        do {
            let data = try JSONEncoder().encode(self)
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: Self.fileURL, options: .atomic)
            return true
        } catch {
            print("[License] 保存失败：\(error.localizedDescription)")
            return false
        }
    }

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/license.json")
    }
}

nonisolated enum BundleIntegrity {
    struct Report: Sendable {
        var signatureValid: Bool
        var executableSHA256: String
        var resourcesSHA256: String
        var detail: String
    }

    static func verify() -> Report {
        let bundle = Bundle.main.bundleURL
        let executableDigest = Bundle.main.executableURL.flatMap(sha256(of:)) ?? ""
        let resourcesDigest = hashResources(bundle.appendingPathComponent("Contents/Resources", isDirectory: true))
        print("【完整性】可执行文件 SHA-256：\(executableDigest.isEmpty ? "空" : executableDigest)")
        print("【完整性】资源目录 SHA-256：\(resourcesDigest.isEmpty ? "空" : resourcesDigest)")
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundle as CFURL, SecCSFlags(rawValue: 0), &code)
        guard created == errSecSuccess, let code else {
            let detail = "无法读取代码签名 status=\(created)"
            print("【完整性】\(detail)")
            return Report(signatureValid: false, executableSHA256: executableDigest, resourcesSHA256: resourcesDigest, detail: detail)
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        let valid = validity == errSecSuccess
        let detail = valid ? "签名与主程序、资源一致" : "签名校验失败 status=\(validity)"
        print("【完整性】\(detail)")
        return Report(signatureValid: valid, executableSHA256: executableDigest, resourcesSHA256: resourcesDigest, detail: detail)
    }

    private static func hashResources(_ root: URL) -> String {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ""
        }
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            print("【完整性】无法读取资源目录：\(root.path)")
            return ""
        }
        var files: [URL] = []
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let size = values?.fileSize ?? 0
            if size > 32_000_000 { continue }
            files.append(file)
        }
        files.sort { $0.path < $1.path }
        var hasher = SHA256()
        for file in files {
            let relative = file.path.replacingOccurrences(of: root.path, with: "")
            hasher.update(data: Data(relative.utf8))
            guard let handle = FileHandle(forReadingAtPath: file.path) else { continue }
            do {
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    hasher.update(data: chunk)
                }
                try handle.close()
            } catch {
                print("【完整性】无法读取 \(file.path)：\(error.localizedDescription)")
                try? handle.close()
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            print("【完整性】无法读取 \(url.path)：\(error.localizedDescription)")
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
