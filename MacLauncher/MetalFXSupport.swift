//
//  MetalFXSupport.swift
//
//  只检测这台 Mac 能不能做 MetalFX 超采样。
//  游戏画面仍由 CrossOver 的 D3DMetal 绘制，Vesta 不把帧送进超采样器。
//

import Foundation
import Metal
import MetalFX

nonisolated enum MetalFXSupport {
    static let spatial: Bool = deviceSupports { MTLFXSpatialScalerDescriptor.supportsDevice($0) }
    static let temporal: Bool = deviceSupports { MTLFXTemporalScalerDescriptor.supportsDevice($0) }
    static var available: Bool { spatial || temporal }

    private static func deviceSupports(_ check: (any MTLDevice) -> Bool) -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return check(device)
    }
}

/// macOS 上的 Wine 多数没有 Linux 的 eventfd FSync。只有二进制里真有实现才启用。
nonisolated enum WineSyncProbe {
    private static let lock = NSLock()
    private static var cached: Bool?

    static func supportsFsync() -> Bool {
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let found = scan()
        guard found != nil else { return false }
        lock.lock()
        cached = found
        lock.unlock()
        return found ?? false
    }

    /// nil 表示 wine64 还不在，先不要把“不支持”记死。
    private static func scan() -> Bool? {
        guard let wine = WineLocator.savedEngineIfPresent() else { return nil }
        let directory = wine.deletingLastPathComponent()
        let needles = [Data("fsync_yield".utf8), Data("do_fsync".utf8)]
        for name in ["wineserver", wine.lastPathComponent] {
            let url = directory.appendingPathComponent(name)
            if fileContains(url, needles: needles) {
                return true
            }
        }
        return false
    }

    private static func fileContains(_ url: URL, needles: [Data]) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? handle.close() }
        let window = 64
        var carry = Data()
        while true {
            let chunk = (try? handle.read(upToCount: 1024 * 256)) ?? Data()
            if chunk.isEmpty { return false }
            let block = carry + chunk
            for needle in needles where block.range(of: needle) != nil {
                return true
            }
            carry = block.suffix(window)
        }
    }
}
