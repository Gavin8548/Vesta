//
//  SystemInfo.swift
//
//  读取当前 Mac 的芯片、系统和内存，供侧边栏和设置页展示。
//

import AppKit
import Darwin
import SwiftUI

struct MacHardware {
    let chip: String
    let system: String
    let memory: String

    static var current: MacHardware {
        MacHardware(chip: chipName(), system: systemVersion(), memory: memorySize())
    }

    private static func chipName() -> String {
        if let brand = sysctlString("machdep.cpu.brand_string"), !brand.isEmpty {
            return brand
        }
        if let model = sysctlString("hw.model"), !model.isEmpty {
            return model
        }
        return "Apple 芯片"
    }

    private static func systemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func memorySize() -> String {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let amount = String(format: "%.0fGB", gigabytes.rounded())
        if chipName().hasPrefix("Apple") {
            return "\(amount) 统一内存"
        }
        return "\(amount) 内存"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MacHardwareSummary: View {
    private let hardware = MacHardware.current
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cpu")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text(.hardwareSummary))
                    .font(.headline)
                Text("\(chipText) / \(memoryText) / \(hardware.system)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var chipText: String {
        hardware.chip == "Apple 芯片" ? language.text(.appleChip) : hardware.chip
    }

    private var memoryText: String {
        SampleCopy.specs(hardware.memory, language: language.currentLanguage)
    }
}

/// 主系统盘或安装目录所在磁盘的容量。单位是十进制 GB，和访达里的显示接近。
nonisolated struct StorageSnapshot: Sendable {
    var totalStorageGB: Double
    var freeStorageGB: Double
}

nonisolated enum StorageMonitor {
    private static let bytesPerGB = 1_000_000_000.0

    static func measure(forPath path: String) -> StorageSnapshot {
        let probe = existingVolumePath(path)
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: probe) else {
            return StorageSnapshot(totalStorageGB: 0, freeStorageGB: 0)
        }
        let total = (attributes[.systemSize] as? NSNumber)?.doubleValue ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        return StorageSnapshot(
            totalStorageGB: total / bytesPerGB,
            freeStorageGB: free / bytesPerGB
        )
    }

    static func gbText(_ value: Double) -> String {
        String(format: "%.0f", value.rounded())
    }

    /// Windows 路径不在本机磁盘上，改查启动盘。Mac 路径则沿用它所在的卷。
    private static func existingVolumePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("\\") {
            return "/"
        }
        var current = (trimmed as NSString).expandingTildeInPath
        let manager = FileManager.default
        while current != "/" && !manager.fileExists(atPath: current) {
            let parent = (current as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == current {
                return "/"
            }
            current = parent
        }
        return current.isEmpty ? "/" : current
    }
}
