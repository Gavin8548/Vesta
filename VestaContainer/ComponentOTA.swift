//
//  ComponentOTA.swift
//
//  只核对已经固定 SHA-256 的 Whisky v3.1.1 运行时。
//  发现别的 GitHub 标签时只提示，不下载、不替换 DXVK、MoltenVK 或 D3DMetal。
//

import Foundation
import SwiftUI

struct ComponentReport: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let canInstallPinned: Bool
}

nonisolated enum ComponentOTAEngine {
    static let pinnedTag = "v3.1.1"
    private static let releaseURL = URL(string: "https://api.github.com/repos/frankea/Whisky/releases/latest")

    static func inspect() -> [ComponentReport] {
        let language = L10n.savedLanguage()
        return [
            wineReport(language: language),
            dxvkReport(language: language),
            moltenReport(language: language),
            metalReport(language: language)
        ]
    }

    static func latestTag() async -> String {
        let language = L10n.savedLanguage()
        guard let releaseURL else {
            return L10n.string(.otaFailed, language: language)
        }
        do {
            var request = URLRequest(url: releaseURL, timeoutInterval: 12)
            request.setValue("Vesta", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return L10n.string(.otaFailed, language: language)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String,
                  !tag.isEmpty else {
                return L10n.string(.otaFailed, language: language)
            }
            if tag == pinnedTag {
                return L10n.string(.otaNoReplace, language: language)
            }
            return L10n.format(.otaNewerUnverified, language, tag)
        } catch {
            print("[OTA] \(error.localizedDescription)")
            return L10n.string(.otaFailed, language: language)
        }
    }

    private static func wineReport(language: AppLanguage) -> ComponentReport {
        if WineLocator.savedEngineIfPresent() != nil {
            return ComponentReport(
                id: "wine",
                title: "Wine",
                detail: L10n.string(.otaWineReady, language: language),
                canInstallPinned: false
            )
        }
        return ComponentReport(
            id: "wine",
            title: "Wine",
            detail: L10n.string(.otaWineMissing, language: language),
            canInstallPinned: true
        )
    }

    private static func dxvkReport(language: AppLanguage) -> ComponentReport {
        ComponentReport(
            id: "dxvk",
            title: "DXVK",
            detail: L10n.string(.otaDXVK, language: language),
            canInstallPinned: false
        )
    }

    private static func moltenReport(language: AppLanguage) -> ComponentReport {
        let found = moltenVKURL() != nil
        return ComponentReport(
            id: "moltenvk",
            title: "MoltenVK",
            detail: L10n.string(found ? .otaMoltenVKFound : .otaMoltenVKMissing, language: language),
            canInstallPinned: false
        )
    }

    private static func metalReport(language: AppLanguage) -> ComponentReport {
        let crossover = HostEngine.resolved() == .crossover
        return ComponentReport(
            id: "d3dmetal",
            title: "D3DMetal",
            detail: L10n.string(crossover ? .otaD3DMetal : .otaD3DMetalWine, language: language),
            canInstallPinned: false
        )
    }

    private static func moltenVKURL() -> URL? {
        guard let wine = WineLocator.savedEngineIfPresent() else { return nil }
        let lib = wine
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib/libMoltenVK.dylib")
        guard FileManager.default.fileExists(atPath: lib.path) else { return nil }
        return lib
    }
}

struct ComponentOTASection: View {
    @EnvironmentObject private var language: LanguageManager
    @ObservedObject private var installer = WineEngineInstaller.shared
    @State private var reports: [ComponentReport] = []
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        Section(language.text(.otaSection)) {
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                    Text(report.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(language.text(.otaCheck), action: check)
                .disabled(busy || installer.isDownloading)
            if reports.contains(where: \.canInstallPinned) {
                Button(language.text(.otaInstallPinned), action: installPinned)
                    .disabled(busy || installer.isDownloading)
            }
            if installer.isDownloading {
                ProgressView(value: Double(installer.percent), total: 100)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { reload() }
        .onChange(of: language.currentLanguage) { _, _ in
            reload()
        }
    }

    private func reload() {
        reports = ComponentOTAEngine.inspect()
    }

    private func check() {
        busy = true
        note = ""
        Task {
            let message = await ComponentOTAEngine.latestTag()
            reload()
            note = message
            busy = false
        }
    }

    private func installPinned() {
        busy = true
        note = ""
        Task {
            do {
                _ = try await WineEngineInstaller.shared.installIfNeeded()
                reload()
                note = language.text(.otaWineReady)
            } catch {
                print("[OTA] \(error.localizedDescription)")
                note = language.text(.otaFailed)
            }
            busy = false
        }
    }
}
