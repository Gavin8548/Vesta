//
//  VestaUserAlert.swift
//
//  把启动和引擎错误显示成中文提示，并给出重新下载或修复容器。
//

import AppKit
import Foundation

@MainActor
enum VestaNotice {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string(.ok, language: L10n.savedLanguage()))
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// 打开官网前先说明要下 Windows 安装包，确认后再交给浏览器。
    static func confirmOfficialDownload(message: String? = nil, open: @escaping @MainActor () -> Void) {
        let language = L10n.savedLanguage()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string(.downloadGuideTitle, language: language)
        if let symbol = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) {
            alert.icon = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 52, weight: .regular))
        }
        let custom = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = custom.isEmpty ? L10n.string(.downloadGuideMessage, language: language) : custom
        alert.accessoryView = noteView(body)
        alert.addButton(withTitle: L10n.string(.goDownload, language: language))
        alert.addButton(withTitle: L10n.string(.cancel, language: language))
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                open()
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    private static func noteView(_ message: String) -> NSView {
        let width: CGFloat = 360
        let label = NSTextField(wrappingLabelWithString: message)
        label.attributedStringValue = emphasized(message)
        label.preferredMaxLayoutWidth = width
        let measured = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 2000)).height ?? 80
        let height = ceil(measured) + 4
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        label.frame = holder.bounds
        label.autoresizingMask = [.width, .height]
        holder.addSubview(label)
        return holder
    }

    private static func emphasized(_ message: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let text = NSMutableAttributedString(
            string: message,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        for highlight in ["Windows (.exe)", "Riot 客户端", "Wine", "腾讯"] {
            if let range = message.range(of: highlight) {
                text.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: NSRange(range, in: message))
            }
        }
        return text
    }
}

@MainActor
enum VestaUserAlert {
    static func explain(_ raw: String) -> String {
        let text = raw.lowercased()
        let language = L10n.savedLanguage()
        if text.contains("权限") || text.contains("permission") || text.contains("wineprefix") || text.contains("容器") {
            return L10n.string(.problemPrefix, language: language)
        }
        if text.contains("校验") || text.contains("损坏") || text.contains("digest") || text.contains("解压") || text.contains("不是有效") {
            return L10n.string(.problemArchive, language: language)
        }
        if text.contains("wine64") || text.contains("引擎") || text.contains("wine") || text.contains("压缩包") {
            return L10n.string(.problemEngine, language: language)
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string(.problemGeneric, language: language)
        }
        return L10n.string(.problemGeneric, language: language)
    }

    static func present(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            print("【Wine严重报错】: \(trimmed)")
        }
        let language = L10n.savedLanguage()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string(.problemTitle, language: language)
        alert.informativeText = explain(trimmed)
        alert.addButton(withTitle: L10n.string(.redownloadEngine, language: language))
        alert.addButton(withTitle: L10n.string(.repairNow, language: language))
        alert.addButton(withTitle: L10n.string(.cancel, language: language))
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                redownload()
            } else if response == .alertSecondButtonReturn {
                repair()
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    private static func redownload() {
        Task { @MainActor in
            do {
                _ = try await WineEngineInstaller.shared.forceRedownload()
            } catch {
                present(error.localizedDescription)
            }
        }
    }

    private static func repair() {
        DispatchQueue.global(qos: .utility).async {
            let prefix = WinePrefixStore.resolve()
            WineProcessCleanup.cleanStaleLocks()
            var writable = FileManager.default.isWritableFile(atPath: prefix.path)
            if !writable {
                do {
                    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
                    writable = FileManager.default.isWritableFile(atPath: prefix.path)
                } catch {
                    print("【WinePrefix】创建失败：\(prefix.path) \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                let language = L10n.savedLanguage()
                let alert = NSAlert()
                alert.alertStyle = writable ? .informational : .warning
                alert.messageText = writable
                    ? L10n.string(.repairDone, language: language)
                    : L10n.string(.problemPrefix, language: language)
                alert.addButton(withTitle: L10n.string(.ok, language: language))
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
    }
}
