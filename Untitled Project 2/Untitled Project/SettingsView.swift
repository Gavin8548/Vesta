//
//  SettingsView.swift
//
//  设置拆成三个独立表单。外观会立刻作用于当前窗口，其余开关只保存界面状态。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsListView: View {
    @Binding var selection: SettingsPane
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        List(selection: $selection) {
            Section(language.text(.preferences)) {
                ForEach(SettingsPane.allCases) { pane in
                    Text(title(for: pane))
                        .tag(pane)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(language.text(.settings))
    }

    private func title(for pane: SettingsPane) -> String {
        switch pane {
        case .general: return language.text(.general)
        case .account: return language.text(.accountSettings)
        case .graphics: return language.text(.graphics)
        case .diagnostics: return language.text(.diagnostics)
        case .feedback: return language.text(.feedbackPane)
        case .about: return language.text(.about)
        case .engine: return language.text(.enginePane)
        }
    }
}

struct SettingsDetailView: View {
    let pane: SettingsPane
    @Binding var appearance: AppearancePreference
    @Binding var restoresLastBottle: Bool
    @Binding var showsRunningInMenuBar: Bool
    @Binding var enablesDXVK: Bool
    @Binding var enablesRetina: Bool
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        paneContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(title(for: pane))
    }

    private func title(for pane: SettingsPane) -> String {
        switch pane {
        case .general: return language.text(.general)
        case .account: return language.text(.accountSettings)
        case .graphics: return language.text(.graphics)
        case .diagnostics: return language.text(.diagnostics)
        case .feedback: return language.text(.feedbackPane)
        case .about: return language.text(.about)
        case .engine: return language.text(.enginePane)
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general:
            GeneralSettingsForm(
                appearance: $appearance,
                restoresLastBottle: $restoresLastBottle,
                showsRunningInMenuBar: $showsRunningInMenuBar
            )
        case .account:
            VestaAccountSettingsView()
        case .graphics:
            GraphicsSettingsForm(
                enablesDXVK: $enablesDXVK,
                enablesRetina: $enablesRetina
            )
        case .diagnostics:
            DiagnosticsSettingsPane()
        case .feedback:
            FeedbackSettingsPane()
        case .about:
            AboutSettingsPane()
        case .engine:
            EngineManagerPane()
        }
    }
}

private struct GeneralSettingsForm: View {
    @Binding var appearance: AppearancePreference
    @Binding var restoresLastBottle: Bool
    @Binding var showsRunningInMenuBar: Bool
    @EnvironmentObject private var language: LanguageManager
    @State private var isCleaningJunk = false
    @State private var junkNote = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text(.languageMenu))
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(AppLanguage.allCases) { item in
                                languageChip(item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                WinePrefixLocationRow()
            }
            Section {
                Button(language.text(.cleanJunk), action: cleanJunk)
                    .disabled(isCleaningJunk)
                if !junkNote.isEmpty {
                    Text(junkNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(language.text(.cleanJunkHint))
            }
            Section {
                Button(language.text(.backupLibrary), action: exportLibrary)
                Button(language.text(.restoreLibrary), action: importLibrary)
                VestaArchiveButtons()
            }
            Section {
                appearancePicker
                Toggle(language.text(.restoreBottle), isOn: $restoresLastBottle)
                Toggle(language.text(.menuBarStatus), isOn: $showsRunningInMenuBar)
            } footer: {
                Text(language.text(.settingsFooter))
            }
            if LaunchSafety.backgroundServicesEnabled {
                ThemeSettingsSection()
            }
        }
        .formStyle(.grouped)
    }

    private func cleanJunk() {
        guard !isCleaningJunk else { return }
        isCleaningJunk = true
        junkNote = ""
        Task {
            let freed = await Task.detached(priority: .utility) {
                StorageMeasure.cleanRuntimeJunk()
            }.value
            junkNote = language.format(.cleanJunkDone, BackupManager.sizeText(freed))
            isCleaningJunk = false
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Vesta-Library.zip"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AppLibraryStore.exportLibraryBackup(to: url)
            VestaNotice.show(title: language.text(.backupLibrary), message: language.text(.libraryBackupDone))
        } catch {
            print("[Library] 备份失败：\(error.localizedDescription)")
            VestaNotice.show(title: language.text(.backupLibrary), message: language.text(.libraryBackupFailed))
        }
    }

    private func importLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AppLibraryStore.restoreLibraryBackup(from: url)
            NotificationCenter.default.post(name: .vestaLibraryRestored, object: nil)
            VestaNotice.show(title: language.text(.restoreLibrary), message: language.text(.libraryRestoreDone))
        } catch {
            print("[Library] 恢复失败：\(error.localizedDescription)")
            VestaNotice.show(title: language.text(.restoreLibrary), message: language.text(.libraryBackupFailed))
        }
    }
}

private struct WinePrefixLocationRow: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var path = WinePrefixStore.resolve().path

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.prefixLocation))
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button(language.text(.choosePrefixFolder)) {
                    if let chosen = WinePrefixStore.chooseWithPanel() {
                        path = chosen.path
                    }
                }
                Button(language.text(.useDesktopPrefix)) {
                    WinePrefixStore.remember(WinePrefixStore.desktopDefault)
                    path = WinePrefixStore.resolve().path
                }
            }
        }
    }
}

private extension GeneralSettingsForm {
    func languageChip(_ item: AppLanguage) -> some View {
        let selected = language.currentLanguage == item
        return Button {
            language.currentLanguage = item
        } label: {
            Text(item.menuTitle)
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var appearancePicker: some View {
        Picker(language.text(.appearance), selection: $appearance) {
            ForEach(AppearancePreference.allCases) { item in
                Text(appearanceTitle(item)).tag(item)
            }
        }
    }

    private func appearanceTitle(_ item: AppearancePreference) -> String {
        switch item {
        case .system: return language.text(.systemAppearance)
        case .light: return language.text(.light)
        case .dark: return language.text(.dark)
        }
    }
}

private struct GraphicsSettingsForm: View {
    @Binding var enablesDXVK: Bool
    @Binding var enablesRetina: Bool
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var license = LicenseManager.shared
    @State private var showsPro = false

    var body: some View {
        Form {
            Section {
                Toggle(language.text(.dxvkExample), isOn: $enablesDXVK)
                    .disabled(!license.hasProAccess)
                Toggle(language.text(.retinaExample), isOn: $enablesRetina)
            } footer: {
                if license.hasProAccess {
                    Text(language.text(.graphicsFooter))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language.text(.proLockedHint))
                        Button(language.text(.buyLicense)) {
                            NSWorkspace.shared.open(LicenseManager.checkoutURL)
                        }
                        Button(language.text(.enterLicense)) { showsPro = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsPro) {
            VestaAuthMembershipView()
                .environmentObject(language)
        }
    }
}

private struct FeedbackSettingsPane: View {
    @EnvironmentObject private var language: LanguageManager

    private let address = "vesta.teamwork@outlook.com"
    private let subject = "Vesta 客户端用户反馈与建议"

    var body: some View {
        ScrollView {
            feedbackCard
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.thinMaterial)
                        .frame(width: 40, height: 40)
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(.feedbackTitle))
                        .font(.headline)
                    Text(address)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text(language.text(.feedbackBody))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: sendFeedback) {
                Text(language.text(.feedbackSend))
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private func sendFeedback() {
        let body = "请在此处输入你的建议或遇到的 Bug：\n\n"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        guard let url = URL(string: "mailto:\(address)?subject=\(encodedSubject)&body=\(encodedBody)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AboutSettingsPane: View {
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IconBadge(systemName: "flame.fill", tint: .orange, size: 64)
                Text("Vesta")
                    .font(.title.weight(.semibold))
                Text(language.text(.productName))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                DetailRow(title: language.text(.version), value: "0.1.0")
                DetailRow(title: language.text(.interfaceLabel), value: "SwiftUI")
                MacHardwareSummary()
                DeviceIdentityCard()
                complianceCard
                acknowledgementCard
                LicenseEntryCard()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var complianceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.complianceTitle))
                .font(.headline)
            Text(language.text(.complianceBody))
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var acknowledgementCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.ackTitle))
                .font(.headline)
            Text(language.text(.ackBody))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            acknowledgementRow(name: "Wine", license: language.text(.wineLicense), note: language.text(.wineNote))
            acknowledgementRow(name: "DXVK", license: "zlib License", note: language.text(.dxvkNote))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func acknowledgementRow(name: String, license: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.semibold))
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

struct VestaAccountSettingsView: View {
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var license = LicenseManager.shared
    @ObservedObject private var account = SupabaseManager.shared
    @State private var showsMembership = false

    private enum SubscriptionKind {
        case trial
        case lifetime
        case expired
    }

    private var subscription: SubscriptionKind {
        if license.isActivated { return .lifetime }
        if license.trialDaysRemaining > 0 { return .trial }
        return .expired
    }

    var body: some View {
        Form {
            accountSection
            serviceSection
            manageSection
            ProfileView()
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsMembership) {
            VestaAuthMembershipView()
                .environmentObject(language)
        }
    }

    private var accountSection: some View {
        Section(language.text(.accountSection)) {
            if account.isAuthenticated {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.currentUserEmail ?? language.text(.accountSignedIn))
                            .font(.headline)
                        Text(language.text(.accountSignedIn))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(language.text(.accountSignOut)) {
                        Task { await account.signOut() }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Text(language.text(.accountSignedOut))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(language.text(.accountSignIn)) {
                        showsMembership = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
            DeviceIdentityCard()
        }
    }

    private var serviceSection: some View {
        Section(language.text(.serviceSection)) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(badgeColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: badgeIcon)
                        .foregroundStyle(badgeColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(serviceTitle)
                            .font(.headline)
                        Spacer()
                        Text(statusBadge)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .foregroundStyle(badgeColor)
                    }
                    Text(serviceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            if subscription != .lifetime {
                Button(action: openCheckout) {
                    Text(language.text(.upgradeLifetime))
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.top, 4)
            }
        }
    }

    private var manageSection: some View {
        Section(language.text(.licenseManageSection)) {
            Button(language.text(.enterSavedLicense)) {
                showsMembership = true
            }
            Button(language.text(.restorePurchases)) {
                license.reloadSavedLicense()
            }
            if let messageKey = license.statusMessageKey {
                Text(language.text(messageKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openCheckout() {
        NSWorkspace.shared.open(LicenseManager.checkoutURL)
    }

    private var serviceTitle: String {
        switch subscription {
        case .trial: return language.text(.serviceTrialTitle)
        case .lifetime: return language.text(.serviceLifetimeTitle)
        case .expired: return language.text(.serviceExpiredTitle)
        }
    }

    private var serviceDescription: String {
        switch subscription {
        case .trial: return language.text(.serviceTrialBody)
        case .lifetime: return language.text(.serviceLifetimeBody)
        case .expired: return language.text(.serviceExpiredBody)
        }
    }

    private var statusBadge: String {
        switch subscription {
        case .trial:
            return language.format(.accountTrialDays, license.trialDaysRemaining)
        case .lifetime:
            return language.text(.lifetimeBadge)
        case .expired:
            return language.text(.expiredBadge)
        }
    }

    private var badgeIcon: String {
        switch subscription {
        case .trial: return "clock.badge.exclamationmark"
        case .lifetime: return "checkmark.seal.fill"
        case .expired: return "exclamationmark.triangle.fill"
        }
    }

    private var badgeColor: Color {
        switch subscription {
        case .trial: return .orange
        case .lifetime: return .green
        case .expired: return .red
        }
    }
}
