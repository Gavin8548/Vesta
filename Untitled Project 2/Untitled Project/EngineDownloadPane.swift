//
//  EngineDownloadPane.swift
//
//  引擎管理里的下载页。只下载已固定 SHA-256 的 Whisky v3.1.1 运行时。
//  CrossOver 和 Game Porting Toolkit 只做本机识别，不提供未校验的安装包。
//

import SwiftUI

struct EngineDownloadPane: View {
    var engines: [EngineInstall]
    var onInstalled: () -> Void
    @ObservedObject private var installer = WineEngineInstaller.shared
    @EnvironmentObject private var language: LanguageManager
    @State private var starting = false
    @State private var failure = ""
    @State private var confirmsRedownload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                runtimeCard
                localCard(
                    title: language.text(.engineOfferCrossoverTitle),
                    detail: language.text(.engineOfferCrossoverDetail),
                    installed: engines.contains { $0.kind == "crossover" }
                )
                localCard(
                    title: language.text(.engineOfferGPTKTitle),
                    detail: language.text(.engineOfferGPTKDetail),
                    installed: engines.contains { $0.kind == "gptk" }
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .confirmationDialog(language.text(.engineRedownloadTitle), isPresented: $confirmsRedownload) {
            Button(language.text(.engineRedownload), role: .destructive) {
                redownload()
            }
            Button(language.text(.supportedClose), role: .cancel) {}
        } message: {
            Text(language.text(.engineRedownloadBody))
        }
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text(.engineOfferWineTitle))
                        .font(.headline)
                    Text("Whisky v3.1.1")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 8)
                statusBadge(installed: vestaInstalled, downloading: busy)
            }
            Text(language.text(.engineOfferWineDetail))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("SHA-256 01f3a1b4…81ccf3")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let size = packageSize {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if busy {
                ProgressView(value: Double(installer.percent), total: 100)
                    .progressViewStyle(.linear)
                Text(progressLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                if vestaInstalled {
                    Button(language.text(.engineInstalledState)) {}
                        .disabled(true)
                    Button(language.text(.engineRedownload)) {
                        confirmsRedownload = true
                    }
                    .disabled(busy)
                } else {
                    Button(language.text(.engineDownloadAction)) {
                        download()
                    }
                    .disabled(busy)
                    .buttonStyle(.borderedProminent)
                }
            }
            if !failure.isEmpty {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func localCard(title: String, detail: String, installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                statusBadge(installed: installed, downloading: false)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(language.text(.engineUnavailable)) {}
                .disabled(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusBadge(installed: Bool, downloading: Bool) -> some View {
        let title: String
        let color: Color
        if downloading {
            title = "\(installer.percent)%"
            color = .accentColor
        } else if installed {
            title = language.text(.engineInstalledState)
            color = .green
        } else {
            title = language.text(.engineDownloadAction)
            color = .secondary
        }
        return Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.16), in: Capsule())
    }

    private var vestaInstalled: Bool {
        engines.contains { $0.kind == "vesta" }
    }

    private var busy: Bool {
        starting || installer.isDownloading
    }

    private var packageSize: String? {
        guard installer.expectedBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: installer.expectedBytes, countStyle: .file)
    }

    private var progressLine: String {
        if installer.phase == .extracting {
            return language.format(.extractingEngine, installer.percent)
        }
        let speed = ByteCountFormatter.string(fromByteCount: Int64(installer.bytesPerSecond.rounded()), countStyle: .file)
        return "\(installer.percent)% · \(speed)/s"
    }

    private func download() {
        guard !busy else { return }
        starting = true
        failure = ""
        Task {
            defer { starting = false }
            do {
                _ = try await installer.downloadPinnedRuntime()
                onInstalled()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func redownload() {
        guard !busy else { return }
        starting = true
        failure = ""
        Task {
            defer { starting = false }
            do {
                _ = try await installer.forceRedownload()
                onInstalled()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
