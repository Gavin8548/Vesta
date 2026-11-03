//
//  DeviceBinding.swift
//
//  用 IOPlatformUUID 生成机器码。登录或激活时把邮箱和这台 Mac 绑在一起，
//  凭证只放进钥匙串。删除 license.json 不会清掉绑定，启动时也不弹钥匙串。
//

import AppKit
import CryptoKit
import Foundation
import IOKit
import Supabase
import SwiftUI

nonisolated enum DeviceFingerprint {
    /// 完整 SHA-256，用来比对。界面上只显示短机器码。
    static let digest: String? = makeDigest()
    static let deviceID: String? = digest.map(shortID)

    private static func makeDigest() -> String? {
        let parts = [platformValue(kIOPlatformUUIDKey), platformValue(kIOPlatformSerialNumberKey)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            print("【设备绑定】读不到主板序列号")
            return nil
        }
        var hasher = SHA256()
        hasher.update(data: Data(parts.joined(separator: "|").utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func shortID(_ digest: String) -> String {
        let hex = String(digest.prefix(16)).uppercased()
        var parts: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
            parts.append(String(hex[index..<next]))
            index = next
        }
        return parts.joined(separator: "-")
    }

    private static func platformValue(_ key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return property.takeRetainedValue() as? String
    }
}

nonisolated struct DeviceCredential: Codable {
    var email: String
    var digest: String
    var deviceID: String
    var licenseKey: String
    var activated: Bool
}

nonisolated enum DeviceCredentialStore {
    private static let account = "device-license"

    static func load() -> DeviceCredential? {
        guard let data = VestaKeychain.load(account: account) else { return nil }
        return try? JSONDecoder().decode(DeviceCredential.self, from: data)
    }

    static func save(_ credential: DeviceCredential) -> Bool {
        guard let data = try? JSONEncoder().encode(credential) else { return false }
        return VestaKeychain.save(data, account: account)
    }
}

enum DeviceBindingResult {
    case accepted
    case otherDevice
    case otherEmail
    case unavailable
    case notSaved
}

enum DeviceBindingError: Error {
    case otherDevice
    case otherEmail
    case unavailable
    case notSaved

    var message: String {
        let language = L10n.savedLanguage()
        switch self {
        case .otherDevice:
            return L10n.string(.deviceBoundElsewhere, language: language)
        case .otherEmail:
            return L10n.string(.deviceBoundOtherEmail, language: language)
        case .unavailable:
            return L10n.string(.deviceIDUnavailable, language: language)
        case .notSaved:
            return L10n.string(.deviceBindFailed, language: language)
        }
    }

    var showsAlert: Bool {
        switch self {
        case .otherDevice, .otherEmail:
            return true
        case .unavailable, .notSaved:
            return false
        }
    }

    static func make(_ result: DeviceBindingResult) -> DeviceBindingError? {
        switch result {
        case .accepted:
            return nil
        case .otherDevice:
            return .otherDevice
        case .otherEmail:
            return .otherEmail
        case .unavailable:
            return .unavailable
        case .notSaved:
            return .notSaved
        }
    }
}

enum DeviceBinding {
    /// 邮箱第一次出现就写下当前机器码。已经绑在别的 Mac 上则拒绝，不覆盖原记录。
    static func claim(email: String?, licenseKey: String, markActivated: Bool) async -> DeviceBindingResult {
        if VestaDevelopmentAccess.enabled {
            return .accepted
        }
        guard let digest = DeviceFingerprint.digest, let deviceID = DeviceFingerprint.deviceID else {
            return .unavailable
        }
        let normalized = normalize(email)
        let existing = DeviceCredentialStore.load()
        if let existing, existing.digest != digest {
            print("【设备绑定】本机钥匙串与当前机器码不一致")
            return .otherDevice
        }
        if let existing, !existing.email.isEmpty, !normalized.isEmpty, existing.email != normalized {
            print("【设备绑定】这台 Mac 已绑定其他邮箱")
            return .otherEmail
        }
        if !normalized.isEmpty {
            switch await remoteLock(digest: digest, deviceID: deviceID) {
            case .other:
                print("【设备绑定】账号已绑定其他设备")
                return .otherDevice
            case .unavailable:
                let alreadyHere = existing?.digest == digest && existing?.email == normalized
                if !alreadyHere {
                    return .notSaved
                }
            case .same, .empty:
                break
            }
        }
        let credential = DeviceCredential(
            email: normalized.isEmpty ? (existing?.email ?? "") : normalized,
            digest: digest,
            deviceID: deviceID,
            licenseKey: licenseKey.isEmpty ? (existing?.licenseKey ?? "") : licenseKey,
            activated: markActivated || (existing?.activated ?? false)
        )
        guard DeviceCredentialStore.save(credential) else {
            print("【设备绑定】钥匙串写入失败")
            return .notSaved
        }
        print("【设备绑定】已绑定机器码 \(deviceID)")
        return .accepted
    }

    /// 启动时只读。文件里的激活状态必须和这台 Mac 的钥匙串一致。
    static func reconcile(_ record: inout LicenseRecord) {
        if VestaDevelopmentAccess.enabled {
            return
        }
        guard let digest = DeviceFingerprint.digest else { return }
        if let credential = DeviceCredentialStore.load(), credential.digest == digest, credential.activated {
            record.activated = true
            if record.key.isEmpty {
                record.key = credential.licenseKey
            }
            _ = record.save()
            return
        }
        guard record.activated else { return }
        record.activated = false
        _ = record.save()
    }

    private static func normalize(_ email: String?) -> String {
        email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private enum RemoteLock {
        case same
        case empty
        case other
        case unavailable
    }

    private static func remoteLock(digest: String, deviceID: String) async -> RemoteLock {
        let metadata: [String: AnyJSON]
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            metadata = session.user.userMetadata
        } catch {
            return .unavailable
        }
        if let stored = metadataString(metadata["vesta_device_digest"]) {
            return stored == digest ? .same : .other
        }
        do {
            _ = try await SupabaseManager.shared.client.auth.update(
                user: UserAttributes(data: [
                    "vesta_device_digest": .string(digest),
                    "vesta_device_id": .string(deviceID)
                ])
            )
        } catch {
            print("【设备绑定】写入账号资料失败：\(error.localizedDescription)")
            return .unavailable
        }
        return .empty
    }

    private static func metadataString(_ value: AnyJSON?) -> String? {
        guard let value else { return nil }
        guard case .string(let text) = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DeviceIdentityCard: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(.deviceIDTitle))
                .font(.headline)
            Text(DeviceFingerprint.deviceID ?? language.text(.deviceIDUnavailable))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text(language.text(.deviceIDHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(language.text(copied ? .deviceIDCopied : .deviceIDCopy), action: copy)
                .disabled(DeviceFingerprint.deviceID == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copy() {
        guard let deviceID = DeviceFingerprint.deviceID else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(deviceID, forType: .string)
        copied = true
    }
}
