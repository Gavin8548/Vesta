//
//  EnvironmentDiagnosticService.swift
//
//  检测 Rosetta 2、标准 wine64，以及系统 libc++ / 容器里的 VC++ 运行库。
//  一键修复会安装缺失的 Rosetta。
//

import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

enum ClinicState {
    case ready
    case partial
    case missing
}

struct ClinicCheck: Identifiable {
    let id: String
    let title: L10nKey
    let detail: L10nKey
    let state: ClinicState
}

@MainActor
final class EnvironmentDiagnosticService: ObservableObject {
    static let shared = EnvironmentDiagnosticService()

    @Published private(set) var checks: [ClinicCheck] = []
    @Published private(set) var isRepairing = false
    @Published private(set) var repairMessageKey: L10nKey?

    private init() {}

    func refresh() {
        guard LaunchSafety.backgroundServicesEnabled else {
            checks = []
            return
        }
        let rosetta = Self.rosettaCheck()
        let whisky = Self.whiskyCheck()
        let cpp = Self.cppCheck()
        checks = [rosetta, whisky, cpp]
    }

    /// 安装缺失的 Rosetta。Wine 未安装时不打开其它应用。
    func repair() async {
        guard LaunchSafety.backgroundServicesEnabled else { return }
        guard !isRepairing else { return }
        isRepairing = true
        repairMessageKey = nil
        let before = Self.scan()
        if before.needsRosetta {
            let installed = await Self.installRosetta()
            refresh()
            if !installed {
                repairMessageKey = .diagRepairFailed
                isRepairing = false
                return
            }
        }
        refresh()
        repairMessageKey = .diagRepairDone
        isRepairing = false
    }

    private static func rosettaCheck() -> ClinicCheck {
        if !isAppleSilicon {
            return ClinicCheck(id: "rosetta", title: .diagRosetta, detail: .diagRosettaIntel, state: .ready)
        }
        if rosettaInstalled {
            return ClinicCheck(id: "rosetta", title: .diagRosetta, detail: .diagRosettaReady, state: .ready)
        }
        return ClinicCheck(id: "rosetta", title: .diagRosetta, detail: .diagRosettaMissing, state: .missing)
    }

    private static func whiskyCheck() -> ClinicCheck {
        if HostEngine.standardWineBinary() != nil {
            return ClinicCheck(id: "whisky", title: .diagWhisky, detail: .diagWhiskyReady, state: .ready)
        }
        return ClinicCheck(id: "whisky", title: .diagWhisky, detail: .diagWhiskyMissing, state: .missing)
    }

    private static func cppCheck() -> ClinicCheck {
        guard FileManager.default.fileExists(atPath: "/usr/lib/libc++.1.dylib") else {
            return ClinicCheck(id: "cpp", title: .diagCpp, detail: .diagCppMissing, state: .missing)
        }
        if vcruntimePresent {
            return ClinicCheck(id: "cpp", title: .diagCpp, detail: .diagCppReady, state: .ready)
        }
        return ClinicCheck(id: "cpp", title: .diagCpp, detail: .diagCppPartial, state: .partial)
    }

    private struct Scan {
        var needsRosetta: Bool
        var whiskyWineReady: Bool
    }

    private static func scan() -> Scan {
        Scan(
            needsRosetta: isAppleSilicon && !rosettaInstalled,
            whiskyWineReady: HostEngine.standardWineBinary() != nil
        )
    }

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    private static var rosettaInstalled: Bool {
        let paths = [
            "/Library/Apple/usr/libexec/oah/libRosettaRuntime",
            "/Library/Apple/usr/share/rosetta/rosetta"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static var vcruntimePresent: Bool {
        let home = NSHomeDirectory()
        let roots = [
            home + "/Library/Application Support/MyApp/Bottles",
            home + "/Library/Application Support/CrossOver/Bottles"
        ]
        let names = ["vcruntime140.dll", "msvcp140.dll"]
        for root in roots {
            guard let bottles = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil
            ) else { continue }
            for bottle in bottles {
                let system32 = bottle.appendingPathComponent("drive_c/windows/system32")
                for name in names {
                    let dll = system32.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: dll.path) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func installRosetta() async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
            ]
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if !errorText.isEmpty {
                    print("[Rosetta] \(errorText)")
                }
                print("[Rosetta] Exit Code: \(process.terminationStatus)")
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                print("[Rosetta] \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }
}

struct DiagnosticsSettingsPane: View {
    @ObservedObject private var clinic = EnvironmentDiagnosticService.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Form {
            Section {
                ForEach(clinic.checks) { check in
                    diagnosticRow(check)
                }
            }
            StorageReportSection()
            ComponentOTASection()
            Section {
                CompatibilityReportCard()
            }
            repairSection
        }
        .formStyle(.grouped)
        .onAppear { clinic.refresh() }
        .onChange(of: language.currentLanguage) { _, _ in
            clinic.refresh()
        }
    }

    private func diagnosticRow(_ check: ClinicCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(language.text(check.title))
                Spacer()
                Text(language.text(label(for: check.state)))
                    .foregroundStyle(color(for: check.state))
            }
            Text(language.text(check.detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var repairSection: some View {
        Section {
            Button(language.text(.repairEnvironment)) {
                Task { await clinic.repair() }
            }
            .disabled(clinic.isRepairing)
            if clinic.isRepairing {
                ProgressView()
            }
        } footer: {
            if let key = clinic.repairMessageKey {
                Text(language.text(key))
            }
        }
    }

    private func label(for state: ClinicState) -> L10nKey {
        switch state {
        case .ready: return .diagReady
        case .partial: return .diagPartial
        case .missing: return .diagMissing
        }
    }

    private func color(for state: ClinicState) -> Color {
        switch state {
        case .ready: return .green
        case .partial: return .orange
        case .missing: return .orange
        }
    }
}
