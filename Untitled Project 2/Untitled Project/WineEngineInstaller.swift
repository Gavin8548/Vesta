//
//  WineEngineInstaller.swift
//
//  本机没有可用的 wine64 时，下载 Whisky 维护的 Wine 11 运行时。
//  解压后递归查找 wine64，赋予执行权限，初始化 WINEPREFIX，再写入 UserDefaults。
//

import Combine
import CryptoKit
import Foundation

@MainActor
final class WineEngineInstaller: ObservableObject {
    static let shared = WineEngineInstaller()

    enum Phase {
        case idle
        case downloading
        case extracting
    }

    @Published private(set) var isDownloading = false
    @Published private(set) var phase: Phase = .idle
    /// 0...100。下载阶段按已接收字节计算，解压阶段按已写出的体积计算。
    @Published private(set) var percent: Int = 0
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = 0
    /// 最近一段时间的平均下载速度，单位是字节/秒。解压阶段为 0。
    @Published private(set) var bytesPerSecond: Double = 0

    func progressText(_ language: LanguageManager) -> String {
        if phase == .extracting {
            return language.format(.extractingEngine, percent)
        }
        return language.format(.downloadingEngine, percent)
    }

    /// Whisky v3.1.1 运行时。直链是 gzip，包内有 Libraries/Wine/bin/wine64。
    private static let packageURL: URL? = URL(string: "https://github.com/frankea/Whisky/releases/download/v3.1.1/Libraries.tar.gz")

    private var installTask: Task<URL, Error>?

    private init() {}

    func applyDownloadPercent(_ value: Int) {
        let clamped = min(max(value, 0), 100)
        guard clamped != percent else { return }
        percent = clamped
    }

    func applyTransfer(percent value: Int, received: Int64, expected: Int64, speed: Double) {
        let clamped = min(max(value, 0), 100)
        if clamped != percent {
            percent = clamped
        }
        receivedBytes = received
        expectedBytes = max(expected, 0)
        bytesPerSecond = speed
    }

    /// 只安装已经校验过的 Whisky v3.1.1 运行时。引擎目录里已有 wine64 时直接登记，不重复下载。
    func downloadPinnedRuntime() async throws -> URL {
        let libraries = WineLocator.engineRoot.appendingPathComponent("Libraries", isDirectory: true)
        let existing = await Task.detached(priority: .utility) {
            WineLocator.findWine64(in: libraries)
        }.value
        if let existing, FileManager.default.isExecutableFile(atPath: existing) {
            WineLocator.remember(existing)
            return URL(fileURLWithPath: existing)
        }
        if let installTask {
            return try await installTask.value
        }
        let task = Task { @MainActor in
            try await self.downloadAndInstall()
        }
        installTask = task
        do {
            let result = try await task.value
            installTask = nil
            return result
        } catch {
            installTask = nil
            throw error
        }
    }

    /// 忽略已经保存的路径，重新下载并解压。供错误弹窗里的「重新下载」使用。
    func forceRedownload() async throws -> URL {
        UserDefaults.standard.removeObject(forKey: WineLocator.defaultsKey)
        if let installTask {
            return try await installTask.value
        }
        let task = Task { @MainActor in
            try await self.downloadAndInstall()
        }
        installTask = task
        do {
            let result = try await task.value
            installTask = nil
            return result
        } catch {
            installTask = nil
            throw error
        }
    }

    /// 已经有可用的 wine64 时直接返回。否则下载、解压、校验并写入 UserDefaults。任一步失败都会抛出具体原因。
    func installIfNeeded() async throws -> URL {
        if let existing = WineLocator.search() {
            guard FileManager.default.fileExists(atPath: existing.path) else {
                throw WineEngineError.missingOnDisk("已记录的 wine64 不存在：\(existing.path)")
            }
            return existing
        }
        if let installTask {
            return try await installTask.value
        }
        let task = Task { @MainActor in
            try await self.downloadAndInstall()
        }
        installTask = task
        do {
            let result = try await task.value
            installTask = nil
            return result
        } catch {
            installTask = nil
            throw error
        }
    }

    private func downloadAndInstall() async throws -> URL {
        isDownloading = true
        phase = .downloading
        percent = 0
        receivedBytes = 0
        expectedBytes = 0
        bytesPerSecond = 0
        InstallGate.setBusy(true)
        defer { InstallGate.setBusy(false) }
        guard let packageURL = Self.packageURL else {
            isDownloading = false
            phase = .idle
            throw WineEngineError.invalidArchive
        }
        print("【下载开始】: \(packageURL.absoluteString)")
        do {
            let archive = try await ArchiveFetcher(url: packageURL).download()
            print("【下载完成】: \(archive.path)")
            phase = .extracting
            percent = 0
            bytesPerSecond = 0
            let installed = try await runOnBackground {
                try Self.installArchive(archive)
            }
            guard FileManager.default.fileExists(atPath: installed.path) else {
                throw WineEngineError.missingOnDisk("写入缓存后 wine64 不存在：\(installed.path)")
            }
            percent = 100
            isDownloading = false
            phase = .idle
            return installed
        } catch {
            isDownloading = false
            phase = .idle
            print("[WineEngine] \(error.localizedDescription)")
            throw error
        }
    }

    private func runOnBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 解压到引擎目录，再递归找出 wine64。调用方已在后台队列。
    private nonisolated static func installArchive(_ archive: URL) throws -> URL {
        let manager = FileManager.default
        _ = try validateArchive(archive)
        defer {
            if manager.fileExists(atPath: archive.path) {
                try? manager.removeItem(at: archive.deletingLastPathComponent())
            }
        }
        let staging = archive.deletingLastPathComponent().appendingPathComponent("extracted", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        print("【解压开始】: \(archive.path)")
        try verifyDigest(archive)
        try extract(archive: archive, to: staging)
        let engineRoot = WineLocator.engineRoot
        if manager.fileExists(atPath: engineRoot.path) {
            try manager.removeItem(at: engineRoot)
        }
        try manager.createDirectory(at: engineRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: staging, to: engineRoot)
        print("【解压成功，目标目录】: \(engineRoot.path)")
        let matches = WineLocator.findAllWine64(in: engineRoot)
        print("[WineEngine] enumerator 找到 \(matches.count) 个 wine64")
        guard !matches.isEmpty else {
            throw WineEngineError.binaryMissing
        }
        for match in matches {
            guard manager.fileExists(atPath: match) else {
                throw WineEngineError.missingOnDisk("递归找到的 wine64 不存在：\(match)")
            }
            print("[WineEngine] fileExists 通过：\(match)")
        }
        let found = matches.first {
            URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent == "bin"
        } ?? matches[0]
        return try commitVerifiedWine64(found)
    }

    /// 找到 wine64 后立刻写入 WineEnginePath。wineboot 失败也不能把这次安装弄丢。
    private nonisolated static func commitVerifiedWine64(_ path: String) throws -> URL {
        let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: absolute) else {
            throw WineEngineError.missingOnDisk("准备授权时 wine64 不存在：\(absolute)")
        }
        UserDefaults.standard.set(absolute, forKey: "WineEnginePath")
        let cached = UserDefaults.standard.string(forKey: "WineEnginePath")
        print("成功保存 Wine 路径: \(absolute)")
        print("【校验缓存】成功读取到保存的 wine64 路径: \(cached ?? "空")")
        guard cached == absolute else {
            throw WineEngineError.cacheMismatch(cached ?? "空")
        }
        try chmodExecutable(absolute)
        guard FileManager.default.fileExists(atPath: absolute) else {
            throw WineEngineError.missingOnDisk("chmod 之后 wine64 不存在：\(absolute)")
        }
        guard FileManager.default.isExecutableFile(atPath: absolute) else {
            throw WineEngineError.notExecutable("chmod 之后 wine64 仍不可执行：\(absolute)")
        }
        if let reason = AppLauncher.initializePrefix(wine64: URL(fileURLWithPath: absolute)) {
            print("【Wine 初始化】wineboot 失败，已保留引擎路径：\(reason)")
            throw WineEngineError.winebootFailed(reason)
        }
        return URL(fileURLWithPath: absolute)
    }

    /// 拒绝 HTML。只接受 gzip 或 zip。
    private nonisolated static func validateArchive(_ url: URL) throws -> ArchiveKind {
        let handle = try FileHandle(forReadingFrom: url)
        let header = try handle.read(upToCount: 16) ?? Data()
        try handle.close()
        let bytes = [UInt8](header)
        let kind: ArchiveKind?
        if bytes.starts(with: [0x1F, 0x8B]) {
            kind = .gzip
        } else if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            kind = .zip
        } else {
            kind = nil
        }
        guard let kind else {
            let preview = String(decoding: header, as: UTF8.self)
            print("[WineEngine] 下载内容不是 tar.gz 或 zip，文件开头：\(preview)")
            throw WineEngineError.invalidArchive
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 1_000_000 else {
            print("[WineEngine] 下载文件过小：\(size) 字节")
            throw WineEngineError.invalidArchive
        }
        return kind
    }

    /// 对照 Whisky 发布的 SHA-256。流式计算，避免把整个压缩包读进内存。
    private nonisolated static func verifyDigest(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        var hasher = SHA256()
        var read: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
            read += Int64(chunk.count)
            if fileSize > 0 {
                reportExtractPercent(Int(read * 20 / fileSize))
            }
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        print("[WineEngine] SHA256 \(digest)")
        guard digest == ArchiveKind.archiveSHA256 else {
            throw WineEngineError.digestMismatch
        }
    }

    /// gzip 用 tar -xzf，zip 用 ditto。FileManager 负责放置解压结果。
    private nonisolated static func extract(archive: URL, to destination: URL) throws {
        let kind = try validateArchive(archive)
        let process = Process()
        switch kind {
        case .gzip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", archive.path, "-C", destination.path]
        case .zip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, destination.path]
        }
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        let monitor = ExtractMonitor(destination: destination, expected: gzipUncompressedSize(archive))
        monitor.start()
        defer { monitor.stop() }
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outputText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !outputText.isEmpty {
            print("[WineEngine] \(outputText)")
        }
        guard process.terminationStatus == 0 else {
            print("[WineEngine] tar Exit Code: \(process.terminationStatus)")
            if !errorText.isEmpty {
                print("[WineEngine] \(errorText)")
            }
            throw WineEngineError.extractFailed(errorText.isEmpty ? "tar \(process.terminationStatus)" : errorText)
        }
    }

    /// `chmod +x <wine64路径>`。调用方已在后台队列。
    private nonisolated static func chmodExecutable(_ path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", path]
        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("[WineEngine] chmod +x \(path)")
        print("[WineEngine] chmod Exit Code: \(process.terminationStatus)")
        if !errorText.isEmpty {
            print("[WineEngine] \(errorText)")
        }
        guard process.terminationStatus == 0 else {
            throw WineEngineError.chmodFailed(errorText.isEmpty ? "chmod \(process.terminationStatus)" : errorText)
        }
    }

    nonisolated static func reportExtractPercent(_ value: Int) {
        let clamped = min(max(value, 0), 99)
        Task { @MainActor in
            WineEngineInstaller.shared.applyDownloadPercent(clamped)
        }
    }

    /// gzip 末尾 4 字节是原始大小。读不到时解压进度只按阶段推进。
    private nonisolated static func gzipUncompressedSize(_ url: URL) -> Int64? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        let end = handle.seekToEndOfFile()
        guard end >= 4 else { return nil }
        handle.seek(toFileOffset: end - 4)
        let data = handle.readData(ofLength: 4)
        guard data.count == 4 else { return nil }
        let value = Int64(UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24))
        return value > 0 ? value : nil
    }
}

/// 解压期间按目标目录里已经写出的字节更新百分比。
nonisolated private final class ExtractMonitor: @unchecked Sendable {
    private let destination: URL
    private let expected: Int64?
    private let queue = DispatchQueue(label: "vesta.extract.progress")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var stopped = false
    private var ticking = false

    init(destination: URL, expected: Int64?) {
        self.destination = destination
        self.expected = expected
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        lock.lock()
        stopped = true
        timer?.cancel()
        timer = nil
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        if stopped || ticking {
            lock.unlock()
            return
        }
        ticking = true
        lock.unlock()
        let size = Self.folderSize(destination)
        let percent: Int
        if let expected, expected > 0 {
            let ratio = min(Double(size) / Double(expected), 1)
            percent = 20 + Int((ratio * 75).rounded(.down))
        } else {
            percent = 40
        }
        WineEngineInstaller.reportExtractPercent(percent)
        lock.lock()
        ticking = false
        lock.unlock()
    }

    private static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}

nonisolated enum InstallGate {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var busy = false

    static func setBusy(_ value: Bool) {
        lock.lock()
        busy = value
        lock.unlock()
    }

    static func isBusy() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return busy
    }
}

nonisolated private enum ArchiveKind {
    case gzip
    case zip
    /// 官方 Whisky v3.1.1 Libraries.tar.gz 的 SHA-256。
    static let archiveSHA256 = "01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"
}

nonisolated private enum WineEngineError: LocalizedError {
    case binaryMissing
    case missingOnDisk(String)
    case cacheMismatch(String)
    case invalidArchive
    case extractFailed(String)
    case chmodFailed(String)
    case notExecutable(String)
    case digestMismatch
    case winebootFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "没有找到可用的兼容引擎，或引擎文件不完整。可以重新下载，也可以先修复容器后再试。"
        case .missingOnDisk(let detail):
            print("[WineEngine] \(detail)")
            return "没有找到可用的兼容引擎，或引擎文件不完整。可以重新下载，也可以先修复容器后再试。"
        case .cacheMismatch(let detail):
            print("[WineEngine] \(detail)")
            return "没有找到可用的兼容引擎，或引擎文件不完整。可以重新下载，也可以先修复容器后再试。"
        case .invalidArchive, .digestMismatch:
            return "引擎压缩包已损坏或无法解压。请重新下载。"
        case .extractFailed(let detail):
            print("[WineEngine] \(detail)")
            return "引擎压缩包已损坏或无法解压。请重新下载。"
        case .chmodFailed(let detail), .notExecutable(let detail):
            print("[WineEngine] \(detail)")
            return "兼容引擎没有获得执行权限。请重新下载后再试。"
        case .winebootFailed(let detail):
            print("[WineEngine] \(detail)")
            return "容器目录暂时无法完成初始化。可以一键修复后再运行。"
        }
    }
}

/// URLSession 下载。进度由 didWriteData 按字节数计算后写入界面。中断后用断点数据重试。
nonisolated private final class ArchiveFetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var didResume = false
    private var didSucceed = false
    private var lastPercent = -1
    private let maxAttempts = 4
    private var sampleBytes: Int64 = 0
    private var sampleTime: CFAbsoluteTime = 0
    private var smoothedSpeed: Double = 0

    init(url: URL) {
        remoteURL = url
    }

    func download() async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VestaWine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("wine.tar.gz")
        var resumeData: Data?
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await performOnce(destination: destination, resumeData: resumeData)
            } catch {
                lastError = error
                print("[WineEngine] 下载失败（第 \(attempt) 次）：\(error.localizedDescription)")
                print("[WineEngine] \(error)")
                let info = (error as NSError).userInfo
                resumeData = info[NSURLSessionDownloadTaskResumeData] as? Data
                guard attempt < maxAttempts else { break }
                print("[WineEngine] \(resumeData == nil ? "重新开始下载" : "从断点继续下载")")
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func performOnce(destination: URL, resumeData: Data?) async throws -> URL {
        self.destination = destination
        resetAttempt()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            begin(continuation)
            if let resumeData {
                session.downloadTask(withResumeData: resumeData).resume()
            } else {
                session.downloadTask(with: remoteURL).resume()
            }
        }
    }

    private func resetAttempt() {
        lock.lock()
        didResume = false
        didSucceed = false
        lastPercent = -1
        sampleBytes = 0
        sampleTime = 0
        smoothedSpeed = 0
        lock.unlock()
    }

    private func begin(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        if sampleTime == 0 {
            sampleTime = now
            sampleBytes = totalBytesWritten
        }
        let elapsed = now - sampleTime
        var speed = smoothedSpeed
        if elapsed >= 0.4 {
            let delta = max(totalBytesWritten - sampleBytes, 0)
            let instant = Double(delta) / elapsed
            speed = smoothedSpeed == 0 ? instant : (smoothedSpeed * 0.6 + instant * 0.4)
            smoothedSpeed = speed
            sampleTime = now
            sampleBytes = totalBytesWritten
        }
        let percent: Int
        if totalBytesExpectedToWrite > 0 {
            percent = Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100).rounded(.down))
        } else {
            percent = lastPercent < 0 ? 0 : lastPercent
        }
        let changed = percent != lastPercent || elapsed >= 0.4
        let percentChanged = percent != lastPercent
        if changed {
            lastPercent = percent
        }
        lock.unlock()
        guard changed else { return }
        if percentChanged {
            print("【下载进度】: \(percent)%")
        }
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            WineEngineInstaller.shared.applyTransfer(
                percent: percent,
                received: totalBytesWritten,
                expected: expected,
                speed: speed
            )
        }
        if percent % 10 == 0 || percent == 100 {
            print("[WineEngine] totalBytesWritten=\(totalBytesWritten) totalBytesExpectedToWrite=\(totalBytesExpectedToWrite) \(percent)%")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination else {
            finish(.failure(URLError(.cannotCreateFile)))
            return
        }
        if let response = downloadTask.response as? HTTPURLResponse {
            let type = response.mimeType ?? ""
            print("[WineEngine] HTTP \(response.statusCode) \(type)")
            guard (200...299).contains(response.statusCode), !type.contains("html") else {
                finish(.failure(WineEngineError.invalidArchive))
                return
            }
        }
        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: location, to: destination)
            lock.lock()
            didSucceed = true
            lock.unlock()
            finish(.success(destination))
        } catch {
            print("[WineEngine] 保存下载文件失败：\(error.localizedDescription)")
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            lock.lock()
            let succeeded = didSucceed
            lock.unlock()
            if succeeded {
                print("[WineEngine] 文件已落地，忽略随后的回调：\(error.localizedDescription)")
            } else {
                print("[WineEngine] 下载中断：\(error.localizedDescription)")
                finish(.failure(error))
            }
        }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let already = didResume
        if continuation != nil {
            didResume = true
        }
        lock.unlock()
        guard !already, let continuation else { return }
        continuation.resume(with: result)
    }
}
