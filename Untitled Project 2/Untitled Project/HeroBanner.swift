//
//  HeroBanner.swift
//
//  详情页顶部的全宽横版海报。高度固定，标题只叠在海报内部。
//

import AppKit
import SwiftUI

struct HeroBanner: View {
    let program: WindowsApp
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .overlay {
                ZStack {
                    AmbientGlow(primary: program.themeGlow, secondary: program.themeGlowSecondary)
                    artwork
                    bottomScrim
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HeroIdentityPlate(program: program, onToggleFavorite: onToggleFavorite)
                    .padding(.leading, 12)
                    .padding(.bottom, 10)
                    .padding(.trailing, 12)
            }
            .overlay(alignment: .topTrailing) {
                HeroStatusChip(program: program)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
            }
            .clipped()
    }

    private var artwork: some View {
        HeroArtwork(program: program)
            .id(program.bannerURL ?? program.id.uuidString)
    }

    /// 底部压暗，标题和标签留在这层上面。
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.45), location: 0.72),
                .init(color: .black.opacity(0.82), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct HeroIdentityPlate: View {
    let program: WindowsApp
    var onToggleFavorite: () -> Void = {}
    @EnvironmentObject private var language: LanguageManager

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
            copy
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background { plate }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: some View {
        AppIconView(
            sources: program.iconSources,
            tint: program.tint.color,
            size: 36,
            cornerRadius: 10,
            fillsFrame: program.iconFillsFrame
        )
        .shadow(color: program.tint.color.opacity(0.55), radius: 8)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Text(program.localizedName(language.currentLanguage))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .lineLimit(1)
                FavoriteStarButton(isFavorite: program.isFavorite, action: onToggleFavorite)
                Spacer(minLength: 0)
            }
            if !program.version.isEmpty {
                Text(program.localizedVersion(language.currentLanguage))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
            HeroTagRow(tags: Array(tags.prefix(3)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }

    private var tags: [String] {
        var items = program.displayTags
        let region = program.regionTitle(language.currentLanguage)
        let alreadyListed = items.contains { $0.caseInsensitiveCompare(region) == .orderedSame }
        if !region.isEmpty, !alreadyListed {
            items.append(region)
        }
        return items
    }
}

private struct HeroStatusChip: View {
    let program: WindowsApp

    var body: some View {
        StatusCapsule(isRunning: program.isRunning, isLaunching: program.isLaunching)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.6)
            }
    }
}

private struct HeroTagRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.16), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
                        }
                }
            }
        }
    }
}

private struct HeroArtwork: View {
    let program: WindowsApp
    @State private var local: NSImage?
    @State private var didCheckLocal = false

    var body: some View {
        ZStack {
            TechWallpaper(tint: program.tint.color)
            if let local {
                FillingArtwork(image: Image(nsImage: local))
            } else if didCheckLocal, !remoteURLs.isEmpty {
                RemoteHero(urls: remoteURLs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: program.id) {
            let image = await BannerSource.loadLocal(program)
            if Task.isCancelled { return }
            local = image
            didCheckLocal = true
        }
    }

    private var remoteURLs: [URL] {
        BannerSource.remoteURLs(for: program)
    }
}

private struct RemoteHero: View {
    let urls: [URL]
    @State private var index = 0

    var body: some View {
        AsyncImage(url: urls[min(index, max(urls.count - 1, 0))]) { phase in
            remotePhase(phase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func remotePhase(_ phase: AsyncImagePhase) -> some View {
        switch phase {
        case .empty:
            Color.clear
        case .success(let image):
            FillingArtwork(image: image)
        default:
            Color.clear
                .onAppear(perform: advance)
        }
    }

    private func advance() {
        guard index + 1 < urls.count else { return }
        index += 1
    }
}

private struct FillingArtwork: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

private struct AmbientGlow: View {
    let primary: Color
    let secondary: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(primary.opacity(0.55))
                .frame(width: 420, height: 280)
                .blur(radius: 70)
                .offset(x: 160, y: -30)
            Circle()
                .fill(secondary.opacity(0.42))
                .frame(width: 340, height: 240)
                .blur(radius: 64)
                .offset(x: -180, y: 70)
        }
        .allowsHitTesting(false)
        .drawingGroup(opaque: false)
    }
}

extension WindowsApp {
    var themeGlow: Color {
        switch regionCode {
        case "cn": return Color(red: 0.45, green: 0.86, blue: 1.0)
        case "ap": return Color(red: 0.05, green: 0.9, blue: 0.78)
        case "na": return Color(red: 1.0, green: 0.32, blue: 0.05)
        case "eu": return Color(red: 0.28, green: 0.58, blue: 1.0)
        default:
            if ambientStyle == "pubg" {
                return Color(red: 0.86, green: 0.62, blue: 0.22)
            }
            return tint.color
        }
    }

    var themeGlowSecondary: Color {
        switch regionCode {
        case "cn": return Color.white
        case "ap": return Color(red: 0.15, green: 0.45, blue: 1.0)
        case "na": return Color(red: 1.0, green: 0.72, blue: 0.15)
        case "eu": return Color(red: 0.95, green: 0.76, blue: 0.32)
        default:
            if ambientStyle == "pubg" {
                return Color(red: 0.72, green: 0.4, blue: 0.18)
            }
            return tint.color
        }
    }
}

struct TechWallpaper: View {
    let tint: Color

    var body: some View {
        ZStack {
            base
            glow
            TechGridLines()
        }
        .drawingGroup(opaque: true)
    }

    private var base: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.11),
                tint.opacity(0.72),
                Color(red: 0.02, green: 0.03, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glow: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.7))
                .frame(width: 260, height: 260)
                .blur(radius: 48)
                .offset(x: 170, y: -36)
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 120, height: 120)
                .blur(radius: 18)
                .offset(x: -190, y: 48)
        }
    }
}

private struct TechGridLines: View {
    var body: some View {
        Canvas { context, size in
            let path = grid(in: size)
            context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private func grid(in size: CGSize) -> Path {
        var path = Path()
        let step: CGFloat = 28
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        return path
    }
}

@MainActor
enum BannerSource {
    private static let localCache = NSCache<NSString, NSImage>()

    static func loadLocal(_ program: WindowsApp) async -> NSImage? {
        let key = [program.bannerImageURL ?? "", program.bannerImage ?? ""].joined(separator: "\n")
        if let cached = localCache.object(forKey: key as NSString) {
            return cached
        }
        let bannerURL = program.bannerImageURL
        let bannerName = program.bannerImage
        let image: NSImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let loaded = fileImage(bannerURL) ?? fileImage(bannerName) ?? catalogImage(bannerName)
                continuation.resume(returning: loaded)
            }
        }
        if let image {
            localCache.setObject(image, forKey: key as NSString)
        }
        return image
    }

    static func localImage(for program: WindowsApp) -> NSImage? {
        if let image = fileImage(program.bannerImageURL) { return image }
        if let image = fileImage(program.bannerImage) { return image }
        return catalogImage(program.bannerImage)
    }

    static func remoteURLs(for program: WindowsApp) -> [URL] {
        var urls: [URL] = []
        if let remote = httpURL(program.bannerURL) {
            urls.append(remote)
        }
        if let hero = SteamArtwork.libraryHeroURL(appID: program.steamAppID) {
            urls.append(hero)
        }
        if let header = program.steamHeaderURL {
            urls.append(header)
        }
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func httpURL(_ raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private static func fileImage(_ raw: String?) -> NSImage? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return nil }
        let path = (trimmed as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private static func catalogImage(_ raw: String?) -> NSImage? {
        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\") else { return nil }
        return NSImage(named: name)
    }
}
