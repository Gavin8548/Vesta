//
//  LibraryComponents.swift
//
//  几个很小的控件。每个 body 只做一件事，避免把颜色三元表达式写进修饰符链。
//

import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum AppIconSource: Hashable {
    case remote(URL)
    case asset(String)
    case symbol(String)
}

enum AppArtwork {
    /// 资源目录或文件路径里的图。SF Symbol 名称不会被当成图片。
    static func localImage(named name: String) -> NSImage? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded), let fileImage = NSImage(contentsOfFile: expanded) {
            return fileImage
        }

        guard let namedImage = NSImage(named: NSImage.Name(trimmed)) else { return nil }
        let hasPixels = namedImage.representations.contains { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
        guard hasPixels else { return nil }
        if NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
            return nil
        }
        return namedImage
    }

    static func symbolName(iconName: String, fallback: String) -> String {
        let primary = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSymbol(primary) { return primary }
        if isSymbol(fallback) { return fallback }
        return "app.fill"
    }

    private static var symbolCache: [String: Bool] = [:]

    private static func isSymbol(_ name: String) -> Bool {
        if let cached = symbolCache[name] { return cached }
        let value = !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        symbolCache[name] = value
        return value
    }

    private static var sourceCache: [String: [AppIconSource]] = [:]

    /// 网络 Logo、本地资源、Steam 图，最后才是 SF Symbol。结果按图标字段缓存，滚动时不再查 SF Symbol。
    static func sources(for app: WindowsApp) -> [AppIconSource] {
        let key = [app.iconURL ?? "", app.customIconName ?? "", app.iconName, app.symbolName, app.steamAppID ?? ""].joined(separator: "\n")
        if let cached = sourceCache[key] {
            return cached
        }
        var sources: [AppIconSource] = []
        if let url = remoteURL(app.iconURL) {
            sources.append(.remote(url))
        }
        let assetName = app.customIconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assetName.isEmpty {
            sources.append(.asset(assetName))
        }
        if let steamLogo = app.steamLogoURL {
            sources.append(.remote(steamLogo))
        }
        sources.append(.symbol(symbolName(iconName: app.iconName, fallback: app.symbolName)))
        if sourceCache.count > 300 {
            sourceCache.removeAll(keepingCapacity: true)
        }
        sourceCache[key] = sources
        return sources
    }

    private static func remoteURL(_ raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

extension WindowsApp {
    var iconSources: [AppIconSource] {
        AppArtwork.sources(for: self)
    }
}

extension AppIconSource {
    fileprivate var cacheToken: String {
        switch self {
        case .remote(let url):
            return "r:" + url.absoluteString
        case .asset(let name):
            return "a:" + name
        case .symbol(let name):
            return "s:" + name
        }
    }
}

/// 列表是否正在滑动。卡片不订阅它，因此滚动本身不会让每一行重新计算 body。
nonisolated final class LibraryScrollGate: @unchecked Sendable {
    static let shared = LibraryScrollGate()

    private let lock = NSLock()
    private var idle = true
    private var waiters: [UUID: Waiter] = [:]

    private final class Waiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?

        func store(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func resume() {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume()
        }
    }

    private init() {}

    var isIdle: Bool {
        lock.lock()
        defer { lock.unlock() }
        return idle
    }

    private var idleToken = 0

    func setIdle(_ value: Bool) {
        lock.lock()
        idleToken += 1
        let token = idleToken
        if !value {
            idle = false
            lock.unlock()
            return
        }
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            self.commitIdle(token)
        }
    }

    private func commitIdle(_ token: Int) {
        lock.lock()
        guard token == idleToken else {
            lock.unlock()
            return
        }
        idle = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.values.forEach { $0.resume() }
    }

    func waitUntilIdle() async {
        if isIdle { return }
        let id = UUID()
        let waiter = Waiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if idle || Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiter.store(continuation)
                waiters[id] = waiter
                lock.unlock()
            }
        } onCancel: {
            let removed: Waiter?
            lock.lock()
            removed = waiters.removeValue(forKey: id)
            lock.unlock()
            removed?.resume()
        }
    }
}

extension View {
    /// 滚动阶段只在 macOS 15 及以上才有。更早的系统保持空闲，不在滑动时启动封面读取。
    @ViewBuilder
    func onLibraryScrollIdle() -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollPhaseChange { _, phase in
                LibraryScrollGate.shared.setIdle(phase == .idle)
            }
        } else {
            self
        }
    }
}

/// 封面解码结果留在内存里。滚动时只读这份缓存，不再为每张卡片重新拉网络或读盘。
@MainActor
final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    struct Face {
        var image: NSImage?
        var symbol: String
    }

    private let images = NSCache<NSString, NSImage>()
    private var faces: [String: Face] = [:]
    private var localMisses = Set<String>()
    private var remoteMisses = Set<String>()
    private var inflight: [String: Task<Lookup, Never>] = [:]
    private let faceLimit = 160

    private enum Lookup {
        case image(NSImage)
        case missing
        case skipped
    }

    nonisolated private final class Bitmap: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    nonisolated private enum Pixel: Sendable {
        case image(Bitmap)
        case missing
        case skipped
    }

    nonisolated private static let session: URLSession = {
        let cache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private init() {
        images.countLimit = 160
        images.totalCostLimit = 32 * 1024 * 1024
    }

    func face(for key: String) -> Face? {
        faces[key]
    }

    /// 返回 nil 表示滑动开始，调用方应等列表停稳后再试。不会把这次跳过记成失败。
    func load(sources: [AppIconSource], key: String, points: CGFloat, abortIfScrolling: Bool) async -> Face? {
        if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
            return nil
        }
        if let cached = faces[key] {
            return cached
        }
        for source in sources {
            if Task.isCancelled { return nil }
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return nil
            }
            switch source {
            case .remote(let url):
                switch await remoteImage(url: url, points: points, abortIfScrolling: abortIfScrolling) {
                case .image(let image):
                    return remember(Face(image: image, symbol: ""), for: key)
                case .missing:
                    continue
                case .skipped:
                    return nil
                }
            case .asset(let name):
                switch await localImage(named: name, points: points, abortIfScrolling: abortIfScrolling) {
                case .image(let image):
                    return remember(Face(image: image, symbol: ""), for: key)
                case .missing:
                    continue
                case .skipped:
                    return nil
                }
            case .symbol(let name):
                return remember(Face(image: nil, symbol: name), for: key)
            }
        }
        return remember(Face(image: nil, symbol: "app.fill"), for: key)
    }

    private func remember(_ face: Face, for key: String) -> Face {
        if faces.count >= faceLimit {
            faces.removeAll(keepingCapacity: true)
        }
        faces[key] = face
        return face
    }

    private func remoteImage(url: URL, points: CGFloat, abortIfScrolling: Bool) async -> Lookup {
        let key = url.absoluteString + "@" + String(Int(points.rounded()))
        if let image = images.object(forKey: key as NSString) {
            return .image(image)
        }
        if remoteMisses.contains(url.absoluteString) {
            return .missing
        }
        if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
            return .skipped
        }
        if let existing = inflight[key] {
            return await existing.value
        }
        let maxPixel = maxPixel(for: points)
        let task = Task<Lookup, Never> {
            let pixel = await Self.remotePixels(
                url: url,
                maxPixel: maxPixel,
                cacheKey: key,
                abortIfScrolling: abortIfScrolling
            )
            switch pixel {
            case .image(let bitmap):
                if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                    return .skipped
                }
                return .image(self.nsImage(bitmap))
            case .missing:
                return .missing
            case .skipped:
                return .skipped
            }
        }
        inflight[key] = task
        let lookup = await task.value
        inflight[key] = nil
        if case .image(let image) = lookup {
            images.setObject(image, forKey: key as NSString, cost: pixelCost(image))
            return lookup
        }
        if case .missing = lookup, !Task.isCancelled {
            remoteMisses.insert(url.absoluteString)
        }
        return lookup
    }

    private func localImage(named name: String, points: CGFloat, abortIfScrolling: Bool) async -> Lookup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .missing }
        let key = "a:" + trimmed + "@" + String(Int(points.rounded()))
        if let image = images.object(forKey: key as NSString) {
            return .image(image)
        }
        if localMisses.contains(key) {
            return .missing
        }
        if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
            return .skipped
        }
        let maxPixel = maxPixel(for: points)
        let pixel = await Self.filePixels(
            name: trimmed,
            maxPixel: maxPixel,
            cacheKey: key,
            abortIfScrolling: abortIfScrolling
        )
        if Task.isCancelled { return .skipped }
        switch pixel {
        case .image(let bitmap):
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            let image = nsImage(bitmap)
            images.setObject(image, forKey: key as NSString, cost: pixelCost(image))
            return .image(image)
        case .skipped:
            return .skipped
        case .missing:
            break
        }
        if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
            return .skipped
        }
        let catalog = await Self.catalogPixels(
            name: trimmed,
            maxPixel: maxPixel,
            cacheKey: key,
            abortIfScrolling: abortIfScrolling
        )
        switch catalog {
        case .image(let bitmap):
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            let image = nsImage(bitmap)
            images.setObject(image, forKey: key as NSString, cost: pixelCost(image))
            return .image(image)
        case .skipped:
            return .skipped
        case .missing:
            localMisses.insert(key)
            return .missing
        }
    }

    private func maxPixel(for points: CGFloat) -> Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return max(Int((points * scale).rounded(.up)), 1)
    }

    private func nsImage(_ bitmap: Bitmap) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(width: CGFloat(bitmap.image.width) / scale, height: CGFloat(bitmap.image.height) / scale)
        return NSImage(cgImage: bitmap.image, size: size)
    }

    private func pixelCost(_ image: NSImage) -> Int {
        let width = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let height = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        return max(width, 1) * max(height, 1) * 4
    }

    nonisolated private static func remotePixels(url: URL, maxPixel: Int, cacheKey: String, abortIfScrolling: Bool) async -> Pixel {
        if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
            return .skipped
        }
        if let cached = await io({ readThumbnail(cacheKey) }) {
            return .image(cached)
        }
        if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
            return .skipped
        }
        guard let data = await fetch(url) else { return .missing }
        return await io {
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            guard let bitmap = makeThumbnail(data: data, maxPixel: maxPixel) else { return .missing }
            writeThumbnail(bitmap.image, key: cacheKey)
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            return .image(bitmap)
        }
    }

    nonisolated private static func filePixels(name: String, maxPixel: Int, cacheKey: String, abortIfScrolling: Bool) async -> Pixel {
        await io {
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            if let cached = readThumbnail(cacheKey) {
                return .image(cached)
            }
            guard let data = fileBytes(name) else { return .missing }
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            guard let bitmap = makeThumbnail(data: data, maxPixel: maxPixel) else { return .missing }
            writeThumbnail(bitmap.image, key: cacheKey)
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            return .image(bitmap)
        }
    }

    nonisolated private static func catalogPixels(name: String, maxPixel: Int, cacheKey: String, abortIfScrolling: Bool) async -> Pixel {
        await io {
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            if let cached = readThumbnail(cacheKey) {
                return .image(cached)
            }
            guard let named = NSImage(named: NSImage.Name(name)) else { return .missing }
            let hasPixels = named.representations.contains { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            guard hasPixels else { return .missing }
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                return .missing
            }
            guard let data = named.tiffRepresentation, let bitmap = makeThumbnail(data: data, maxPixel: maxPixel) else {
                return .missing
            }
            writeThumbnail(bitmap.image, key: cacheKey)
            if abortIfScrolling && !LibraryScrollGate.shared.isIdle {
                return .skipped
            }
            return .image(bitmap)
        }
    }

    nonisolated private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    nonisolated private static func fileBytes(_ name: String) -> Data? {
        let expanded = (name as NSString).expandingTildeInPath
        guard expanded.contains("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return try? Data(contentsOf: URL(fileURLWithPath: expanded), options: [.mappedIfSafe])
    }

    nonisolated private static func makeThumbnail(data: Data, maxPixel: Int) -> Bitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return Bitmap(cgImage)
    }

    nonisolated private static func io<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }

    nonisolated private static var thumbFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vesta/ArtworkCache/Thumbs", isDirectory: true)
    }

    nonisolated private static func thumbURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return thumbFolder.appendingPathComponent(name).appendingPathExtension("png")
    }

    nonisolated private static func readThumbnail(_ key: String) -> Bitmap? {
        let url = thumbURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return Bitmap(cgImage)
    }

    nonisolated private static func writeThumbnail(_ image: CGImage, key: String) {
        try? FileManager.default.createDirectory(at: thumbFolder, withIntermediateDirectories: true)
        let url = thumbURL(for: key)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

/// 按 iconURL、本地资源、Steam、SF Symbol 的顺序显示图标。
struct AppIconView: View {
    let sources: [AppIconSource]
    let tint: Color
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 12
    var fillsFrame: Bool = false
    /// 游戏库列表传入 true：滑动期间只显示已在内存里的图，不停下来不读盘、不解码。
    var pausesWhileScrolling: Bool = false
    @State private var image: NSImage?
    @State private var symbolName: String?

    private var cacheKey: String {
        let tokens = sources.map(\.cacheToken).joined(separator: "|")
        return tokens + "@" + String(Int(size.rounded()))
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: cacheKey) {
                await resolve()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let shown = resolvedImage {
            fitted(Image(nsImage: shown))
        } else {
            symbolFace(fallbackSymbol)
        }
    }

    private var resolvedImage: NSImage? {
        if let image {
            return image
        }
        return ArtworkImageCache.shared.face(for: cacheKey)?.image
    }

    private var fallbackSymbol: String {
        if let symbolName, !symbolName.isEmpty {
            return symbolName
        }
        if let face = ArtworkImageCache.shared.face(for: cacheKey), face.image == nil, !face.symbol.isEmpty {
            return face.symbol
        }
        for source in sources {
            if case .symbol(let name) = source, !name.isEmpty {
                return name
            }
        }
        return "app.fill"
    }

    private func resolve() async {
        if let face = ArtworkImageCache.shared.face(for: cacheKey) {
            apply(face)
            return
        }
        while !Task.isCancelled {
            if pausesWhileScrolling {
                await LibraryScrollGate.shared.waitUntilIdle()
                if Task.isCancelled { return }
                if let face = ArtworkImageCache.shared.face(for: cacheKey) {
                    apply(face)
                    return
                }
            }
            guard let face = await ArtworkImageCache.shared.load(
                sources: sources,
                key: cacheKey,
                points: size,
                abortIfScrolling: pausesWhileScrolling
            ) else {
                if !pausesWhileScrolling || Task.isCancelled { return }
                continue
            }
            if Task.isCancelled { return }
            apply(face)
            return
        }
    }

    private func apply(_ face: ArtworkImageCache.Face) {
        if let loaded = face.image {
            image = loaded
            symbolName = nil
        } else {
            image = nil
            symbolName = face.symbol.isEmpty ? "app.fill" : face.symbol
        }
    }

    @ViewBuilder
    private func fitted(_ image: Image) -> some View {
        if fillsFrame {
            image
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(symbolBackground)
                .clipped()
        } else {
            image
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
                .padding(size * 0.14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(symbolBackground)
        }
    }

    private func symbolFace(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(symbolBackground)
    }

    private var symbolBackground: some View {
        LinearGradient(
            colors: [tint, tint.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct IconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FavoriteStarButton: View {
    let isFavorite: Bool
    let action: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Image(systemName: isFavorite ? "star.fill" : "star")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { action() })
            .help(language.text(isFavorite ? .unfavorite : .favorite))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(language.text(isFavorite ? .unfavorite : .favorite))
            .accessibilityAction(.default, action)
    }
}

struct StatusCapsule: View {
    let isRunning: Bool
    var isLaunching: Bool = false
    @EnvironmentObject private var language: LanguageManager

    private var title: String {
        if isLaunching || isRunning { return language.text(.running) }
        return language.text(.notRunning)
    }

    private var tint: Color {
        if isLaunching { return .orange }
        return isRunning ? .green : .secondary
    }

    var body: some View {
        Group {
            if isLaunching {
                LaunchingStatusText(fallback: title, tint: tint)
            } else {
                statusLabel(title)
            }
        }
    }

    private func statusLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// 只有正在下载引擎时才订阅安装进度，避免每张卡片在闲置时跟着刷新。
struct LaunchingStatusText: View {
    let fallback: String
    let tint: Color
    @ObservedObject private var engineInstaller = WineEngineInstaller.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Text(engineInstaller.isDownloading ? engineInstaller.progressText(language) : fallback)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// 下载或解压引擎时贴在主窗口顶部，百分比来自已接收字节或已解压体积。
struct EngineProgressBanner: View {
    @ObservedObject private var installer = WineEngineInstaller.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        if installer.isDownloading {
            VStack(alignment: .leading, spacing: 6) {
                Text(installer.progressText(language))
                    .font(.callout.weight(.medium))
                ProgressView(value: Double(installer.percent), total: 100)
                    .progressViewStyle(.linear)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

/// 有官方直链时用系统浏览器打开，没有则置灰并提示暂无直链。
struct OfficialDownloadButton: View {
    let urlString: String?
    var readyTitle: String? = nil
    var guideMessage: String? = nil
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var language: LanguageManager

    private var destination: URL? {
        let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let url = URL(string: raw) else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    var body: some View {
        Button {
            guard let destination else { return }
            VestaNotice.confirmOfficialDownload(message: guideMessage) {
                openURL(destination)
            }
        } label: {
            Label(
                destination == nil ? language.text(.noDirectLink) : (readyTitle ?? language.text(.browserDownload)),
                systemImage: "safari"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .disabled(destination == nil)
        .help(destination == nil ? language.text(.noDirectLink) : (destination?.absoluteString ?? ""))
    }
}

struct TagCapsuleRow: View {
    let tags: [String]
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        isOn ? Color.accentColor : Color.primary.opacity(0.05)
    }
}

struct KindCapsule: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

struct InlineBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

/// 列表卡片用一层不透明底色。透明绘制和离屏成图会在滑动时按帧重绘。
struct SelectableCard<Content: View>: View {
    let isSelected: Bool
    let content: Content

    init(isSelected: Bool, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(fillColor) }
            .overlay { shape.strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1) }
            .drawingGroup(opaque: false)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var fillColor: Color {
        let base = NSColor.controlBackgroundColor
        guard isSelected else { return Color(nsColor: base) }
        let mixed = base.blended(withFraction: 0.22, of: .controlAccentColor) ?? base
        return Color(nsColor: mixed)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.85)
        }
        return Color.primary.opacity(0.1)
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            clearButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: fieldShape)
        .overlay(fieldShape.strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .accessibilityLabel(language.text(.searchApps))
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    @ViewBuilder
    private var clearButton: some View {
        if !text.isEmpty {
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(language.text(.clearSearch))
        }
    }

    private func clear() {
        text = ""
    }
}

struct ExeImportButtonView: View {
    var onImport: () -> Void
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Button(action: onImport) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text(language.text(.importExe))
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(language.text(.importHelp))
    }
}

/// 把 .exe、.app 或游戏文件夹拖进库。悬停时边框变蓝，松手后交给现有导入流程。
struct ImportDropZone: View {
    var onDrop: (URL, Bool) -> Void
    @EnvironmentObject private var language: LanguageManager
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.title2)
                .foregroundStyle(isTargeted ? Color.blue : Color.secondary)
            Text(language.text(isTargeted ? .importDropReady : .importDropHint))
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(isTargeted ? Color.blue : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.blue.opacity(0.14) : Color.primary.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.blue : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25, dash: [7, 4])
                )
        }
        .animation(.easeInOut(duration: 0.16), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: receiveDrop)
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                deliver(object)
            }
            return true
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                deliver(url)
            } else if let data = item as? Data {
                deliver(URL(dataRepresentation: data, relativeTo: nil))
            }
        }
        return provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    private func deliver(_ url: URL?) {
        guard let url else { return }
        let started = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            onDrop(url, started)
        }
    }
}

/// 系统文件面板：.app、.exe 和文件夹都能选。`.app` 按包选择，不拆开进目录。
@MainActor
enum ImportPanel {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        let language = L10n.savedLanguage()
        panel.title = L10n.string(.importExe, language: language)
        panel.message = L10n.string(.importHelp, language: language)
        panel.prompt = L10n.string(.ok, language: language)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        var types: [UTType] = [.application, .folder, .data]
        if let exe = UTType(filenameExtension: "exe") {
            types.append(exe)
        }
        panel.allowedContentTypes = types
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

/// 把用户选中的应用、exe 或文件夹解析成一条可以写入库的记录。
nonisolated enum LibraryImport {
    struct Item: Sendable {
        var name: String
        var sourcePath: String
        var installPath: String
        var isMacApp: Bool
        var bookmark: Data?
    }

    enum Failure: Error, Sendable {
        case unsupported
        case copyFailed(String)
    }

    static func load(_ url: URL, bottleName: String) -> Result<Item, Failure> {
        let selected = url.standardizedFileURL
        if isAppBundle(selected) {
            return .success(macItem(selected))
        }
        if selected.pathExtension.lowercased() == "exe" {
            return windowsItem(selected, bottleName: bottleName)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.unsupported)
        }
        if isWinePrefix(selected) {
            let drive = selected.appendingPathComponent("drive_c", isDirectory: true)
            let root = FileManager.default.fileExists(atPath: drive.path) ? drive : selected
            if let exe = bestExecutable(in: root, folderName: selected.lastPathComponent) {
                return windowsItem(exe, bottleName: bottleName)
            }
        }
        if let app = bestApplication(in: selected) {
            return .success(macItem(app))
        }
        if let exe = bestExecutable(in: selected, folderName: selected.lastPathComponent) {
            return windowsItem(exe, bottleName: bottleName)
        }
        return .failure(.unsupported)
    }

    private static func macItem(_ url: URL) -> Item {
        Item(
            name: bundleName(url),
            sourcePath: url.path,
            installPath: url.path,
            isMacApp: true,
            bookmark: ImportedFileAccess.bookmark(for: url)
        )
    }

    private static func windowsItem(_ source: URL, bottleName: String) -> Result<Item, Failure> {
        do {
            let windowsPath = try BottleActions.installImportedExecutable(from: source, bottleName: bottleName)
            return .success(Item(
                name: source.deletingPathExtension().lastPathComponent,
                sourcePath: source.path,
                installPath: windowsPath,
                isMacApp: false,
                bookmark: ImportedFileAccess.bookmark(for: source)
            ))
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
    }

    private static func isAppBundle(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path)
    }

    private static func isWinePrefix(_ url: URL) -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.appendingPathComponent("drive_c").path) { return true }
        if manager.fileExists(atPath: url.appendingPathComponent("system.reg").path) { return true }
        return manager.fileExists(atPath: url.appendingPathComponent("user.reg").path)
    }

    private static func bundleName(_ url: URL) -> String {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plist),
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func bestApplication(in root: URL) -> URL? {
        let folder = root.lastPathComponent
        let apps = collect(in: root, maxDepth: 3, where: isAppBundle)
        return apps.min { lhs, rhs in
            let leftMatch = lhs.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folder) == .orderedSame
            let rightMatch = rhs.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folder) == .orderedSame
            if leftMatch != rightMatch { return leftMatch }
            return lhs.pathComponents.count < rhs.pathComponents.count
        }
    }

    private static func bestExecutable(in root: URL, folderName: String) -> URL? {
        let files = collect(in: root, maxDepth: 5) { $0.pathExtension.lowercased() == "exe" }
        guard !files.isEmpty else { return nil }
        let usable = files.filter { !isSkippedExe($0) }
        let pool = usable.isEmpty ? files : usable
        let folder = folderName.lowercased()
        return pool.max { score($0, folder: folder) < score($1, folder: folder) }
    }

    private static func score(_ url: URL, folder: String) -> Int {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        var value = fileSize(url)
        if stem == folder || (!folder.isEmpty && (folder.contains(stem) || stem.contains(folder))) {
            value += 1_000_000_000_000
        }
        return value
    }

    private static func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private static let skippedExeStems: Set<String> = [
        "uninstall", "unins000", "uninstaller", "setup", "vcredist", "vc_redist",
        "dxsetup", "unitycrashhandler", "crashpad_handler", "redist"
    ]

    private static func isSkippedExe(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        if skippedExeStems.contains(stem) { return true }
        return stem.hasPrefix("unins") || stem.contains("vcredist") || stem.contains("vc_redist")
    }

    private static func collect(in root: URL, maxDepth: Int, where matches: (URL) -> Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        let rootDepth = root.pathComponents.count
        var found: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if item.pathComponents.count - rootDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if shouldSkipTree(item) {
                enumerator.skipDescendants()
                continue
            }
            guard FileManager.default.fileExists(atPath: item.path) else { continue }
            if matches(item) {
                found.append(item)
                if item.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }

    private static func shouldSkipTree(_ url: URL) -> Bool {
        let lower = url.path.lowercased()
        if lower.contains("/windows/system32") { return true }
        if lower.contains("/windows/syswow64") { return true }
        if lower.contains("/windows/winsxs") { return true }
        return false
    }
}

/// 列表顶部：数量说明、导入按钮、搜索框。搜索框单独占一行，窄栏也不挤。
struct BrowserHeader: View {
    let subtitle: String
    @Binding var query: String
    let searchPrompt: String
    let onImport: () -> Void
    let onDropImport: (URL, Bool) -> Void
    var secondaryTitle: String?
    var secondarySymbol: String?
    var onSecondary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ExeImportButtonView(onImport: onImport)
            ImportDropZone(onDrop: onDropImport)
            secondaryButton
            SearchField(prompt: searchPrompt, text: $query)
        }
        .padding(16)
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if let secondaryTitle, let secondarySymbol, let onSecondary {
            Button(action: onSecondary) {
                Label(secondaryTitle, systemImage: secondarySymbol)
            }
        }
    }
}

struct PlaceholderPane: View {
    let title: String
    let systemImage: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            actionButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let buttonTitle, let action {
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct VestaGlass: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(Color.white.opacity(0.05)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }
}

extension View {
    func vestaGlass(cornerRadius: CGFloat = 18) -> some View {
        modifier(VestaGlass(cornerRadius: cornerRadius))
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
