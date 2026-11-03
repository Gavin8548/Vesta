//
//  ThemeManager.swift
//
//  高亮色和启动器壁纸。壁纸是原创渐变，或用户自己的图片。
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum LauncherAccent: String, CaseIterable, Identifiable {
    case dark
    case techBlue
    case vaporwave

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .dark:
            return Color(red: 0.78, green: 0.80, blue: 0.84)
        case .techBlue:
            return Color(red: 0.28, green: 0.62, blue: 1.0)
        case .vaporwave:
            return Color(red: 1.0, green: 0.38, blue: 0.78)
        }
    }
}

enum WallpaperPreset: String, CaseIterable, Identifiable {
    case none
    case night
    case ink
    case orbit
    case custom

    var id: String { rawValue }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var accent: LauncherAccent {
        didSet {
            guard isReady, accent != oldValue else { return }
            UserDefaults.standard.set(accent.rawValue, forKey: Self.accentKey)
        }
    }

    @Published var wallpaper: WallpaperPreset {
        didSet {
            guard isReady, wallpaper != oldValue else { return }
            UserDefaults.standard.set(wallpaper.rawValue, forKey: Self.wallpaperKey)
        }
    }

    @Published private(set) var customImagePath: String {
        didSet {
            guard isReady, customImagePath != oldValue else { return }
            UserDefaults.standard.set(customImagePath, forKey: Self.imageKey)
        }
    }

    private var isReady = false
    private static let accentKey = "MyApp.accent"
    private static let wallpaperKey = "MyApp.wallpaper"
    private static let imageKey = "MyApp.wallpaperPath"

    private init() {
        let accentRaw = UserDefaults.standard.string(forKey: Self.accentKey) ?? ""
        accent = LauncherAccent(rawValue: accentRaw) ?? .techBlue
        let wallpaperRaw = UserDefaults.standard.string(forKey: Self.wallpaperKey) ?? ""
        wallpaper = WallpaperPreset(rawValue: wallpaperRaw) ?? .none
        customImagePath = UserDefaults.standard.string(forKey: Self.imageKey) ?? ""
        isReady = true
        print("[MyApp] ThemeManager ready")
    }

    var accentColor: Color { accent.color }

    func importWallpaper(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let folder = wallpaperFolder()
        let destination = folder.appendingPathComponent("background-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            customImagePath = destination.path
            wallpaper = .custom
        } catch {
            return
        }
    }

    private func wallpaperFolder() -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyApp/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

struct ThemeWallpaper: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        canvas
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var canvas: some View {
        switch theme.wallpaper {
        case .none:
            Color.clear
        case .night:
            night
        case .ink:
            ink
        case .orbit:
            orbit
        case .custom:
            custom
        }
    }

    private var night: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.12), Color(red: 0.12, green: 0.02, blue: 0.18)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1, green: 0.3, blue: 0.7).opacity(0.35)).frame(width: 420).blur(radius: 40).offset(x: 220, y: -80)
            Circle().fill(Color(red: 0.2, green: 0.8, blue: 1).opacity(0.28)).frame(width: 360).blur(radius: 36).offset(x: -180, y: 160)
        }
    }

    private var ink: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.07), Color(red: 0.22, green: 0.16, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.95, green: 0.78, blue: 0.35).opacity(0.22)).frame(width: 480).blur(radius: 50).offset(x: 40, y: -120)
        }
    }

    private var orbit: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.05, blue: 0.1), Color(red: 0.05, green: 0.16, blue: 0.28)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 80).stroke(Color.white.opacity(0.16), lineWidth: 18).frame(width: 520, height: 220).rotationEffect(.degrees(-18)).offset(y: 40)
        }
    }

    @ViewBuilder
    private var custom: some View {
        if let image = NSImage(contentsOfFile: theme.customImagePath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .opacity(0.55)
        } else {
            night
        }
    }
}

struct ThemeSettingsSection: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var language: LanguageManager
    @State private var isPickingImage = false
    @State private var isDropTargeted = false

    var body: some View {
        Section(language.text(.themeSection)) {
            Picker(language.text(.accentColor), selection: $theme.accent) {
                Text(language.text(.accentDark)).tag(LauncherAccent.dark)
                Text(language.text(.accentTechBlue)).tag(LauncherAccent.techBlue)
                Text(language.text(.accentVaporwave)).tag(LauncherAccent.vaporwave)
            }
            wallpaperPicker
            wallpaperWell
            Button(language.text(.chooseWallpaper)) {
                isPickingImage = true
            }
        }
        .fileImporter(isPresented: $isPickingImage, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            theme.importWallpaper(from: url)
        }
    }

    private var wallpaperPicker: some View {
        Picker(language.text(.wallpaper), selection: $theme.wallpaper) {
            Text(language.text(.wallpaperNone)).tag(WallpaperPreset.none)
            Text(language.text(.wallpaperNight)).tag(WallpaperPreset.night)
            Text(language.text(.wallpaperInk)).tag(WallpaperPreset.ink)
            Text(language.text(.wallpaperOrbit)).tag(WallpaperPreset.orbit)
            if theme.wallpaper == .custom {
                Text(language.text(.chooseWallpaper)).tag(WallpaperPreset.custom)
            }
        }
    }

    private var wallpaperWell: some View {
        ZStack {
            ThemeWallpaper()
            Text(language.text(.wallpaperDrop))
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 1)
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object else { return }
                Task { @MainActor in
                    ThemeManager.shared.importWallpaper(from: url)
                }
            }
            return true
        }
        return false
    }
}
