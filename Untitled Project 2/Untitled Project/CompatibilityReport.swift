//
//  CompatibilityReport.swift
//
//  把本机游戏库和内置目录做一次比对，并写成 Markdown。
//  只在用户点击后运行，不在启动时扫描。
//

import AppKit
import SwiftUI

nonisolated struct CompatibilityReportResult: Sendable {
    var succeeded: Bool
    var message: String
    var filePath: String
}

nonisolated enum CompatibilityReport {
    static func write(library: [LibraryProbe]) -> CompatibilityReportResult {
        let matches = library.map { probe in
            LibraryMatch(probe: probe, record: GameCompatibilityCatalog.match(name: probe.name, steamAppID: probe.steamAppID))
        }
        let text = document(matches: matches, generated: Date())
        do {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let url = folder.appendingPathComponent("Vesta_Game_Compatibility_Report.md")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return CompatibilityReportResult(succeeded: true, message: url.path, filePath: url.path)
        } catch {
            return CompatibilityReportResult(succeeded: false, message: error.localizedDescription, filePath: "")
        }
    }

    private static func document(matches: [LibraryMatch], generated: Date) -> String {
        let stamp = generated.formatted(date: .abbreviated, time: .shortened)
        let native = GameCompatibilityCatalog.records(in: .native)
        let tunable = GameCompatibilityCatalog.records(in: .tunable)
        let blocked = GameCompatibilityCatalog.records(in: .blocked)
        var lines: [String] = []
        lines.append("# Vesta 主流游戏兼容性报告")
        lines.append("")
        lines.append("生成时间：\(stamp)")
        lines.append("")
        lines.append("这份报告使用 Vesta 内置目录，按游戏名称和 Steam 编号与本机游戏库比对。它不是网页爬虫，也没有在这台 Mac 上逐款启动或测量帧率。")
        lines.append("")
        lines.append("- 绿色：有官方 macOS 版本，不经过 Wine。")
        lines.append("- 黄色：没有已知的内核级反作弊，但仍要放进容器并调优。")
        lines.append("- 红色：内核级反作弊，或根本没有可在 macOS / Windows 容器里运行的正式版本。")
        lines.append("")
        lines.append("目录共 \(native.count + tunable.count + blocked.count) 款。本机游戏库 \(matches.count) 款，其中对上目录 \(matches.filter { $0.record != nil }.count) 款。")
        lines.append("")
        lines.append("## 本机游戏库比对")
        lines.append("")
        if matches.isEmpty {
            lines.append("当前游戏库是空的。")
        } else {
            lines.append("| 游戏 | 来源 | 分类 | 说明 |")
            lines.append("| --- | --- | --- | --- |")
            for item in matches {
                let source = item.probe.imported ? "本地导入" : "内置目录"
                let shown = localLine(item)
                lines.append("| \(escape(item.probe.name)) | \(source) | \(shown.label) | \(escape(shown.reason)) |")
            }
        }
        lines.append("")
        appendSection(&lines, title: "🟢 官方 macOS 版本", records: native)
        appendSection(&lines, title: "🟡 容器可尝试，需要调优", records: tunable)
        appendSection(&lines, title: "🔴 无法运行", records: blocked)
        lines.append("## 使用界限")
        lines.append("")
        lines.append("反作弊软件会更新。某款游戏从黄色变成红色时，以它是否要求内核驱动为准。Vesta 不会因为这份文档去下载游戏，也不会改写 Wine 启动参数。")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func appendSection(_ lines: inout [String], title: String, records: [CompatibilityRecord]) {
        lines.append("## \(title)")
        lines.append("")
        lines.append("| 游戏 | 原因 |")
        lines.append("| --- | --- |")
        for record in records {
            lines.append("| \(escape(record.title)) | \(escape(record.reason)) |")
        }
        lines.append("")
    }

    private static func localLine(_ item: LibraryMatch) -> (label: String, reason: String) {
        guard let record = item.record else {
            return ("未收录", "目录里没有这款游戏，不能据此判断能不能运行。")
        }
        if record.tier == .native, item.probe.platform != "macOS" {
            return ("🟡 有 macOS 版，当前是 Windows 构建", "官方有 macOS 版本。这条记录是 Windows 路径，仍要放进容器，不能把它当成已经原生运行。")
        }
        return (tierTitle(record.tier), record.reason)
    }

    private static func tierTitle(_ tier: CompatibilityTier) -> String {
        switch tier {
        case .native: return "🟢 官方 macOS"
        case .tunable: return "🟡 容器可尝试"
        case .blocked: return "🔴 无法运行"
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}

struct CompatibilityReportCard: View {
    @EnvironmentObject private var language: LanguageManager
    @State private var busy = false
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(.compatReport))
                .font(.headline)
            Text(language.text(.compatReportHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(language.text(.compatReport)) {
                generate()
            }
            .disabled(busy)
            if busy {
                ProgressView()
                    .controlSize(.small)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func generate() {
        guard !busy else { return }
        busy = true
        note = ""
        var programs = WindowsApp.samples.filter { app in
            !GameRemoval.isBlocked(app.name) && !GameRemoval.isHidden(app.playtimeKey)
        }
        AppLibraryStore.load(into: &programs)
        let probes = programs.map { app in
            LibraryProbe(
                name: app.name,
                steamAppID: app.steamAppID ?? "",
                platform: app.platform == .macOS ? "macOS" : "Windows",
                imported: app.isUserImported
            )
        }
        Task {
            let result = await Task.detached(priority: .utility) {
                CompatibilityReport.write(library: probes)
            }.value
            note = result.succeeded
                ? language.format(.compatReportDone, result.filePath)
                : result.message
            if result.succeeded {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.filePath)])
            }
            busy = false
        }
    }
}
