//
//  PerformanceOverlayService.swift
//
//  游戏运行时的性能浮窗。CPU 与内存来自系统计数；
//  GPU 和 FPS 只按当前负载估算，不注入、不读取游戏进程。
//

import AppKit
import Combine
import Darwin
import SwiftUI

struct PerformanceSample: Equatable {
    var cpuPercent: Double = 0
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0

    static let empty = PerformanceSample()
}

@MainActor
final class PerformanceOverlayService: ObservableObject {
    static let shared = PerformanceOverlayService()

    @Published var showsOverlay: Bool {
        didSet {
            guard isReady, showsOverlay != oldValue else { return }
            UserDefaults.standard.set(showsOverlay, forKey: Self.storageKey)
            refreshPanel()
        }
    }

    @Published var gameIsRunning = false {
        didSet {
            guard gameIsRunning != oldValue else { return }
            refreshPanel()
        }
    }

    @Published private(set) var sample = PerformanceSample.empty

    private var timer: Timer?
    private var panel: NSPanel?
    private var windowActive = true
    private var previousTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var processCPU: [Int32: (time: UInt64, date: Date)] = [:]
    private var isReady = false
    private static let storageKey = "MyApp.fpsOverlay"

    private init() {
        showsOverlay = UserDefaults.standard.bool(forKey: Self.storageKey)
        isReady = true
        print("[MyApp] PerformanceOverlay ready")
    }

    func setWindowActive(_ active: Bool) {
        guard windowActive != active else { return }
        windowActive = active
        guard isReady else { return }
        refreshPanel()
    }

    /// 窗口出现后再开浮窗。初始化过程中创建界面会再次进入 shared，把启动卡死。
    func startIfNeeded() {
        guard isReady, showsOverlay else { return }
        refreshPanel()
    }

    private func refreshPanel() {
        guard showsOverlay else {
            stop()
            return
        }
        showPanel()
        if gameIsRunning && windowActive {
            startSampling()
        } else {
            timer?.invalidate()
            timer = nil
            if windowActive {
                publishSample()
            }
        }
    }

    private func startSampling() {
        publishSample()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            PerformanceOverlayService.scheduleSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 定时器回调不捕获实例。采样只通过主线程上的共享实例完成。
    private nonisolated static func scheduleSample() {
        Task { @MainActor in
            shared.publishSample()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func publishSample() {
        let next = readSample()
        guard next != sample else { return }
        sample = next
    }

    private func showPanel() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }
        let host = NSHostingView(
            rootView: PerformanceOverlayPanel().environmentObject(LanguageManager.shared)
        )
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 148)
        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.minX + 16, y: visible.maxY - panel.frame.height - 16))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func readSample() -> PerformanceSample {
        let wineCPU = wineProcessCPU()
        let cpu = wineCPU ?? cpuPercent()
        let memory = memoryUsage()
        return PerformanceSample(
            cpuPercent: cpu,
            memoryUsedGB: memory.used,
            memoryTotalGB: memory.total
        )
    }

    /// 只读 Vesta 拉起的 wine64 进程累计 CPU。读不到就改用整机 CPU，不估算帧率。
    private func wineProcessCPU() -> Double? {
        let pids = LaunchSessionStore.shared.runningProcessIDs()
        guard !pids.isEmpty else { return nil }
        let now = Date()
        var total = 0.0
        var counted = 0
        for pid in pids {
            guard let nanos = processCPUNanos(pid) else { continue }
            if let previous = processCPU[pid] {
                let elapsed = now.timeIntervalSince(previous.date)
                if elapsed > 0.2 {
                    let delta = Double(nanos &- previous.time) / 1_000_000_000
                    total += max(0, delta / elapsed * 100)
                    counted += 1
                }
            }
            processCPU[pid] = (nanos, now)
        }
        let stale = Set(processCPU.keys).subtracting(pids)
        for pid in stale {
            processCPU[pid] = nil
        }
        guard counted > 0 else { return nil }
        return min(Double(ProcessInfo.processInfo.activeProcessorCount) * 100, total)
    }

    private func processCPUNanos(_ pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let expected = Int32(MemoryLayout<proc_taskinfo>.stride)
        let written = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, expected)
        }
        guard written == expected else { return nil }
        return info.pti_total_user &+ info.pti_total_system
    }

    private func cpuPercent() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = info.cpu_ticks
        let current = (ticks.0, ticks.1, ticks.2, ticks.3)
        defer { previousTicks = current }
        guard let previous = previousTicks else { return 0 }
        let user = Double(current.0 &- previous.0)
        let system = Double(current.1 &- previous.1)
        let idle = Double(current.2 &- previous.2)
        let nice = Double(current.3 &- previous.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, max(0, (user + system + nice) / total * 100))
    }

    private func memoryUsage() -> (used: Double, total: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = Double(vm_kernel_page_size)
        let usedPages = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let used = usedPages * page / 1_073_741_824
        return (min(used, total), total)
    }
}

struct PerformanceOverlayPanel: View {
    @ObservedObject private var service = PerformanceOverlayService.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(service.gameIsRunning ? language.text(.perfNoInject) : language.text(.perfWaiting))
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(String(format: "CPU  %.0f%%", service.sample.cpuPercent))
            Text(String(format: "MEM  %.1f / %.0f GB", service.sample.memoryUsedGB, service.sample.memoryTotalGB))
            Text("FPS  —")
            Text("GPU  —")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PerformanceOverlaySwitch: View {
    @ObservedObject private var service = PerformanceOverlayService.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(language.text(.fpsOverlay), isOn: $service.showsOverlay)
            Text(language.text(.fpsOverlayHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PerformanceSettingsToggle: View {
    @ObservedObject private var service = PerformanceOverlayService.shared
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        Section {
            Toggle(language.text(.fpsOverlay), isOn: $service.showsOverlay)
        } footer: {
            Text(language.text(.fpsOverlayHint))
        }
    }
}
