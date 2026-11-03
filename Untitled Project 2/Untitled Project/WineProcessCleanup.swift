//
//  WineProcessCleanup.swift
//
//  退出时结束残留的 Wine 进程。启动时只清理已经没有进程持有的锁和管道。
//

import Foundation

nonisolated enum WineProcessCleanup {
    /// 主程序退出时调用。没有匹配进程时 killall 会返回非 0，这不是故障。
    static func terminateLingeringWine() {
        let executable = "/usr/bin/killall"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            print("【Wine严重报错】: \(executable) 不可执行")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-9", "wineserver", "wine64"]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            print("【Wine严重报错】: \(error.localizedDescription)")
            return
        }
        process.waitUntilExit()
        let outputText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if !outputText.isEmpty {
            print("【Wine标准输出】: \(outputText)")
        }
        if !errorText.isEmpty {
            print("【Wine严重报错】: \(errorText)")
        }
        print("【Process终止】Exit Code: \(process.terminationStatus)")
    }

    /// 只删除 Vesta 容器和临时下载目录里已经失效的套接字、管道和锁文件。
    static func cleanStaleLocks() {
        if wineProcessIsAlive() {
            print("【Wine 清理】仍有 Wine 进程，跳过锁文件清理")
            return
        }
        let prefix = WinePrefixStore.resolve()
        removeStaleEntries(in: prefix, recursive: false)
        removeStaleEntries(in: prefix.appendingPathComponent("server", isDirectory: true), recursive: true)
        removeLeftoverDownloads()
    }

    private static func wineProcessIsAlive() -> Bool {
        processExists("wineserver") || processExists("wine64")
    }

    /// 无法确认进程是否存在时返回 true，避免误删正在使用的锁。
    private static func processExists(_ name: String) -> Bool {
        let executable = "/usr/bin/pgrep"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            print("【Wine严重报错】: \(executable) 不可执行")
            return true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-x", name]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            print("【Wine严重报错】: \(error.localizedDescription)")
            return true
        }
        process.waitUntilExit()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        print("【Process终止】Exit Code: \(process.terminationStatus)")
        return process.terminationStatus == 0
    }

    private static func removeStaleEntries(in directory: URL, recursive: Bool) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let keys: Set<URLResourceKey> = [.fileResourceTypeKey, .isDirectoryKey]
        let children: [URL]
        do {
            children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        } catch {
            print("【Wine 清理】无法读取：\(directory.path) \(error.localizedDescription)")
            return
        }
        for child in children {
            let values = try? child.resourceValues(forKeys: keys)
            let type = values?.fileResourceType
            let name = child.lastPathComponent
            let stale = type == .socket || type == .namedPipe || name == "lock" || name.lowercased().hasSuffix(".lock")
            if stale {
                do {
                    try manager.removeItem(at: child)
                    print("【Wine 清理】已删除残留：\(child.path)")
                } catch {
                    print("【Wine 清理】删除失败：\(child.path) \(error.localizedDescription)")
                }
                continue
            }
            if recursive, values?.isDirectory == true {
                removeStaleEntries(in: child, recursive: true)
            }
        }
    }

    private static func removeLeftoverDownloads() {
        guard !InstallGate.isBusy() else { return }
        let manager = FileManager.default
        let root = manager.temporaryDirectory
        let children: [URL]
        do {
            children = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            print("【Wine 清理】无法读取临时目录：\(error.localizedDescription)")
            return
        }
        for child in children where child.lastPathComponent.hasPrefix("VestaWine-") {
            do {
                try manager.removeItem(at: child)
                print("【Wine 清理】已删除残留：\(child.path)")
            } catch {
                print("【Wine 清理】删除失败：\(child.path) \(error.localizedDescription)")
            }
        }
    }
}
