import AppKit
import Combine
import Foundation
import Supabase

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    private static let endpoint: URL = {
        if let url = URL(string: "https://dcjizvqlqfczxxzafdrn.supabase.co") {
            return url
        }
        return URL(fileURLWithPath: "/dev/null")
    }()

    /// 会话放在 UserDefaults，不使用 GoTrue 默认的 Keychain。避免每次编译后弹出登录钥匙串授权。
    let client = SupabaseClient(
        supabaseURL: endpoint,
        supabaseKey: "sb_publishable_iTo6Swk1IWG1xfVRYzp1tA_FQH84mgi",
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(storage: UserDefaultsAuthStorage())
        )
    )

    @Published var isAuthenticated = false
    @Published var currentUserEmail: String?

    // 1. 发送 6 位数邮箱验证码 (OTP) - 注意是 signInWithOTP (OTP大写)
    func sendOTP(email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    // 2. 验证用户输入的 6 位数验证码
    func verifyOTP(email: String, code: String) async throws {
        _ = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: .email
        )
        let binding = await DeviceBinding.claim(email: email, licenseKey: "", markActivated: false)
        if let error = DeviceBindingError.make(binding) {
            try? await client.auth.signOut()
            throw error
        }
        isAuthenticated = true
        currentUserEmail = email
    }

    // 3. 退出登录
    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("[Auth] 退出登录没有完成：\(error.localizedDescription)")
        }
        isAuthenticated = false
        currentUserEmail = nil
    }

    @Published var profile: UserProfile?

    func fetchProfile() async throws -> UserProfile? {
        let userId = try await client.auth.session.user.id
        let rows: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        let loaded = rows.first
        profile = loaded
        return loaded
    }

    func updateProfile(username: String, birthday: Date, avatarData: Data?) async throws {
        let userId = try await client.auth.session.user.id
        var avatarURL = profile?.avatarUrl
        if let avatarData {
            let path = "\(userId.uuidString.lowercased())/avatar.jpg"
            let jpeg = Self.jpegData(from: avatarData) ?? avatarData
            try await client.storage
                .from("avatars")
                .upload(
                    path,
                    data: jpeg,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            avatarURL = try client.storage
                .from("avatars")
                .getPublicURL(path: path, cacheNonce: String(Int(Date().timeIntervalSince1970)))
                .absoluteString
        }

        let row = ProfileUpsert(
            id: userId,
            username: username,
            avatarUrl: avatarURL,
            birthday: UserProfile.dayString(from: birthday)
        )
        try await client
            .from("profiles")
            .upsert(row, onConflict: "id")
            .execute()
        profile = UserProfile(id: userId, username: username, avatarUrl: avatarURL, birthday: birthday)
        isAuthenticated = true
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

struct UserProfile: Decodable, Identifiable {
    let id: UUID
    var username: String?
    var avatarUrl: String?
    var birthday: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarUrl = "avatar_url"
        case birthday
    }

    init(id: UUID, username: String?, avatarUrl: String?, birthday: Date?) {
        self.id = id
        self.username = username
        self.avatarUrl = avatarUrl
        self.birthday = birthday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        if let raw = try container.decodeIfPresent(String.self, forKey: .birthday) {
            birthday = Self.dayFormatter.date(from: String(raw.prefix(10)))
        } else {
            birthday = nil
        }
    }

    static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// GoTrue 会话的本地缓存。只读写 UserDefaults，不调用 SecItem，因此不会弹出钥匙串。
nonisolated final class UserDefaultsAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix = "Vesta.supabase.auth."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func store(key: String, value: Data) throws {
        defaults.set(value, forKey: prefix + key)
    }

    func retrieve(key: String) throws -> Data? {
        defaults.data(forKey: prefix + key)
    }

    func remove(key: String) throws {
        defaults.removeObject(forKey: prefix + key)
    }
}

private struct ProfileUpsert: Encodable {
    let id: UUID
    let username: String
    let avatarUrl: String?
    let birthday: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarUrl = "avatar_url"
        case birthday
    }
}

