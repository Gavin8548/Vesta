//
//  LicenseManager.swift
//
//  试用天数在本机计算。在线激活会先联系购买页，再把密钥保存在这台 Mac。
//  购买页没有订单回传接口，因此不会把一次网络访问说成商店已确认付款。
//

import Combine
import SwiftUI

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    /// 购买页。在线商店尚未接入订单回传。
    static var purchaseURL: URL {
        if let url = URL(string: "https://gumroad.com") {
            return url
        }
        return URL(fileURLWithPath: "/")
    }

    /// 真实的 Stripe Payment Link。打不开时仍回退到购买页。打开浏览器不代表商店已确认付款。
    static let stripePaymentURL = "https://buy.stripe.com/00w28r14b4RD1Rg65WbV601"

    static var checkoutURL: URL {
        let isPlaceholder = stripePaymentURL.contains("your_payment_link_here")
        if !isPlaceholder, let stripe = URL(string: stripePaymentURL) {
            return stripe
        }
        return purchaseURL
    }

    @Published private(set) var isActivated = false
    @Published private(set) var trialDaysRemaining: Int
    @Published private(set) var statusMessageKey: L10nKey?
    @Published private(set) var isActivating = false

    private var record: LicenseRecord

    /// 已激活，或仍在试用期内，才能使用 DXVK / Metal / Esync。开发阶段直接视为专业版。
    var hasProAccess: Bool {
        VestaDevelopmentAccess.enabled || record.allowsAdvanced
    }

    var savedKey: String {
        record.key
    }

    var statusTitle: String {
        statusTitle(for: L10n.savedLanguage())
    }

    func statusTitle(for language: AppLanguage) -> String {
        if isActivated {
            return L10n.string(.activated, language: language)
        }
        if trialDaysRemaining > 0 {
            return L10n.format(.trialRemaining, language, trialDaysRemaining)
        }
        return L10n.string(.notActivated, language: language)
    }

    private init() {
        var loaded = LicenseRecord.load()
        if VestaDevelopmentAccess.enabled {
            record = loaded
            isActivated = true
            trialDaysRemaining = record.trialDaysRemaining
            LicenseGate.shared.setAdvanced(true)
            return
        }
        DeviceBinding.reconcile(&loaded)
        record = loaded
        isActivated = record.activated
        trialDaysRemaining = record.trialDaysRemaining
        LicenseGate.shared.setAdvanced(record.allowsAdvanced)
    }

    /// 密钥太短会拒绝。格式完整时先访问购买页，再把授权记在这台 Mac 上。
    func activateOnline(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            statusMessageKey = .keyTooShort
            return
        }
        guard !isActivating else { return }
        isActivating = true
        let binding = await DeviceBinding.claim(
            email: SupabaseManager.shared.currentUserEmail,
            licenseKey: trimmed,
            markActivated: true
        )
        if binding != .accepted {
            switch binding {
            case .otherDevice:
                statusMessageKey = .deviceBoundElsewhere
            case .otherEmail:
                statusMessageKey = .deviceBoundOtherEmail
            case .accepted, .unavailable, .notSaved:
                statusMessageKey = .deviceBindFailed
            }
            if let error = DeviceBindingError.make(binding), error.showsAlert {
                VestaNotice.show(title: L10n.string(.deviceBindTitle, language: L10n.savedLanguage()), message: error.message)
            }
            isActivating = false
            return
        }
        let online = await Self.purchaseHostResponded()
        var updated = record
        updated.key = trimmed
        updated.activated = true
        guard updated.save() else {
            statusMessageKey = .licenseKeychainFailed
            isActivating = false
            return
        }
        record = updated
        isActivated = true
        trialDaysRemaining = record.trialDaysRemaining
        LicenseGate.shared.setAdvanced(record.allowsAdvanced)
        statusMessageKey = online ? .activationSaved : .activationOffline
        isActivating = false
    }

    /// 只重新读取钥匙串里的激活码，不查询云端账单。
    func reloadSavedLicense() {
        record = LicenseRecord.load()
        trialDaysRemaining = record.trialDaysRemaining
        if VestaDevelopmentAccess.enabled {
            isActivated = true
            LicenseGate.shared.setAdvanced(true)
            statusMessageKey = .licenseRestoredLocal
            return
        }
        isActivated = record.activated
        LicenseGate.shared.setAdvanced(record.allowsAdvanced)
        statusMessageKey = isActivated ? .licenseRestoredLocal : .licenseRestoreEmpty
    }

    private static func purchaseHostResponded() async -> Bool {
        var request = URLRequest(url: purchaseURL, timeoutInterval: 8)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}

struct LicenseStatusBadge: View {
    @ObservedObject private var license = LicenseManager.shared
    @EnvironmentObject private var language: LanguageManager
    @State private var showsEntry = false

    var body: some View {
        Button {
            showsEntry = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: license.isActivated ? "checkmark.seal.fill" : "clock.fill")
                Text(license.statusTitle(for: language.currentLanguage))
                    .lineLimit(2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(license.isActivated ? Color.green : Color.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                (license.isActivated ? Color.green : Color.orange).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(language.text(.licenseHelp))
        .sheet(isPresented: $showsEntry) {
            VestaAuthMembershipView()
                .environmentObject(language)
        }
    }
}

struct LicenseEntryCard: View {
    var body: some View {
        VestaAuthMembershipView(embedded: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VestaAuthMembershipView: View {
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var license = LicenseManager.shared
    @ObservedObject private var account = SupabaseManager.shared
    @State private var selectedTab: AuthTab = .login
    @State private var email = ""
    @State private var emailCode = ""
    @State private var emailCodeSent = false
    @State private var isEmailAuthLoading = false
    @State private var phoneNumber = ""
    @State private var countryCode = CountryCode.preferred.code
    @State private var countryName = CountryCode.preferred.nameZh
    @State private var licenseKeyInput = ""
    @State private var authMethod: AuthMethod = .email
    @State private var errorMessage = ""

    private enum AuthTab {
        case login
        case licenseKey
    }

    private enum AuthMethod {
        case email
        case phone
    }

    var body: some View {
        framed
    }

    private var framed: some View {
        panel
            .padding(24)
            .frame(maxWidth: embedded ? .infinity : 420)
            .frame(width: embedded ? nil : 420, height: embedded ? nil : panelHeight)
            .onAppear(perform: loadSavedKey)
    }

    private var panelHeight: CGFloat {
        license.isActivated ? 420 : 480
    }

    private var panel: some View {
        VStack(spacing: 20) {
            if license.isActivated {
                unlocked
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        brand
                        modePicker
                        if selectedTab == .login {
                            loginSection
                        } else {
                            licenseKeySection
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if !embedded {
                Button(language.text(.close)) { dismiss() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 6) {
            Image(systemName: "flame.circle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text("Vesta Pro Hub")
                .font(.title2.bold())
            Text(language.text(.vestaAuthSubtitle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }

    private var modePicker: some View {
        Picker("", selection: $selectedTab) {
            Text(language.text(.authTabAccount)).tag(AuthTab.login)
            Text(language.text(.authTabKey)).tag(AuthTab.licenseKey)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var loginSection: some View {
        VStack(spacing: 16) {
            methodPicker
            if authMethod == .email {
                emailForm
            } else {
                phoneForm
            }
            if authMethod == .phone {
                notice
            }
        }
        .padding(.horizontal)
    }

    private var methodPicker: some View {
        Picker("", selection: $authMethod) {
            Text(language.text(.authEmail)).tag(AuthMethod.email)
            Text(language.text(.authPhone)).tag(AuthMethod.phone)
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 4)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            if account.isAuthenticated {
                Label(account.currentUserEmail ?? language.text(.accountSignedIn), systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(language.text(.authEmailPlaceholder), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(emailCodeSent || isEmailAuthLoading)
                if emailCodeSent {
                    TextField(language.text(.authEmailCode), text: $emailCode)
                        .textFieldStyle(.roundedBorder)
                    Button(language.text(.authConfirmLogin)) {
                        Task { await verifyEmailCode() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isEmailAuthLoading)
                } else {
                    Button(language.text(.authSendLink)) {
                        Task { await sendEmailCode() }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isEmailAuthLoading || !emailLooksValid)
                }
                if isEmailAuthLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("@")
    }

    private var phoneForm: some View {
        PhoneNumberLoginForm(
            selectedCountryName: $countryName,
            selectedCode: $countryCode,
            phoneNumber: $phoneNumber,
            onRequestCode: showAccountLoginUnavailable
        )
    }

    private var licenseKeySection: some View {
        VStack(spacing: 16) {
            Text(language.text(.authKeyHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                TextField(language.text(.authKeyPlaceholder), text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button(language.text(.authActivate)) {
                    validateKey()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(license.isActivating || licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if license.isActivating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            notice
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var notice: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else if let messageKey = license.statusMessageKey, !license.isActivated {
            Text(language.text(messageKey))
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unlocked: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(language.text(.membershipUnlocked))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(language.text(.membershipUnlockedDetail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let messageKey = license.statusMessageKey {
                Text(language.text(messageKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func loadSavedKey() {
        if licenseKeyInput.isEmpty {
            licenseKeyInput = license.savedKey
        }
    }

    private func showAccountLoginUnavailable() {
        errorMessage = language.text(.authUnavailable)
    }

    private func sendEmailCode() async {
        errorMessage = ""
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isEmailAuthLoading = true
        defer { isEmailAuthLoading = false }
        do {
            try await account.sendOTP(email: trimmed)
            emailCodeSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyEmailCode() async {
        let token = emailCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 6 else {
            errorMessage = language.text(.authCodeInvalid)
            return
        }
        errorMessage = ""
        isEmailAuthLoading = true
        defer { isEmailAuthLoading = false }
        do {
            try await account.verifyOTP(email: email, code: token)
        } catch let error as DeviceBindingError {
            errorMessage = error.message
            if error.showsAlert {
                VestaNotice.show(title: language.text(.deviceBindTitle), message: error.message)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validateKey() {
        let trimmed = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else {
            errorMessage = language.text(.keyTooShort)
            return
        }
        errorMessage = ""
        Task { await license.activateOnline(trimmed) }
    }
}
