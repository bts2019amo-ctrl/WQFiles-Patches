import Foundation
import SwiftUI

enum AppAccentPalette: String, CaseIterable, Identifiable {
    case orange
    case blue
    case purple
    case green
    case pink
    case red
    case teal
    case cyan
    case yellow
    case indigo
    case lavender
    case gold
    case lime
    case crimson
    case sky
    case magenta
    case slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return Color(red: 0.92, green: 0.40, blue: 0.16)
        case .blue: return Color(red: 0.16, green: 0.45, blue: 0.95)
        case .purple: return Color(red: 0.55, green: 0.30, blue: 0.90)
        case .green: return Color(red: 0.12, green: 0.62, blue: 0.36)
        case .pink: return Color(red: 0.92, green: 0.25, blue: 0.52)
        case .red: return Color(red: 0.88, green: 0.18, blue: 0.20)
        case .teal: return Color(red: 0.08, green: 0.62, blue: 0.66)
        case .cyan: return Color(red: 0.05, green: 0.78, blue: 0.88)
        case .yellow: return Color(red: 0.98, green: 0.78, blue: 0.12)
        case .indigo: return Color(red: 0.30, green: 0.32, blue: 0.92)
        case .lavender: return Color(red: 0.70, green: 0.52, blue: 0.96)
        case .gold: return Color(red: 0.92, green: 0.60, blue: 0.14)
        case .lime: return Color(red: 0.56, green: 0.78, blue: 0.12)
        case .crimson: return Color(red: 0.72, green: 0.08, blue: 0.24)
        case .sky: return Color(red: 0.22, green: 0.62, blue: 0.96)
        case .magenta: return Color(red: 0.78, green: 0.16, blue: 0.72)
        case .slate: return Color(red: 0.55, green: 0.57, blue: 0.59)
        }
    }
}

enum AppTheme {
    static let accentPaletteStorageKey = "theme.accent.palette"
    static let glassOpacityStorageKey = "theme.glass.opacity"
    static let wallpaperBlurStorageKey = "theme.wallpaper.blur"
    static let animationSpeedStorageKey = "theme.animation.speed"
    static let saturationStorageKey = "theme.saturation"
    static let defaultAccentPalette = AppAccentPalette.slate.rawValue
    static let defaultGlassOpacity = 0.14
    static let defaultWallpaperBlur = 26.0
    static let defaultAnimationSpeed = 1.0
    static let defaultSaturation = 1.0

    static var accent: Color { Color(remoteHex: UserDefaults.standard.string(forKey: "WQRemoteTheme.accentColor") ?? "#a3ff12") }
    static var glassOpacity: Double { UserDefaults.standard.object(forKey: glassOpacityStorageKey) as? Double ?? defaultGlassOpacity }
    static var wallpaperBlur: CGFloat { CGFloat(UserDefaults.standard.object(forKey: wallpaperBlurStorageKey) as? Double ?? defaultWallpaperBlur) }
    static var animationSpeed: Double { UserDefaults.standard.object(forKey: animationSpeedStorageKey) as? Double ?? defaultAnimationSpeed }
    static var saturation: Double { UserDefaults.standard.object(forKey: saturationStorageKey) as? Double ?? defaultSaturation }
    static var pageBackground: Color { Color(remoteHex: UserDefaults.standard.string(forKey: "WQRemoteTheme.backgroundColor") ?? "#000000") }
    static var consoleBackground: Color { Color(remoteHex: UserDefaults.standard.string(forKey: "WQRemoteTheme.surfaceColor") ?? "#0d1b16") }
    static var remoteOpacity: Double { max(0.10, min(1.0, Double(UserDefaults.standard.integer(forKey: "WQRemoteTheme.opacityPercent")) / 100.0)) }
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 14
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16
}
struct ParticleFieldBackground: View {
    @AppStorage("WQRemoteTheme.backgroundColor") private var remoteBackground = "#000000"
    @AppStorage("WQRemoteTheme.accentColor") private var remoteAccent = "#a3ff12"
    @AppStorage("WQRemoteTheme.mutedColor") private var remoteMuted = "#8da69a"
    @AppStorage("WQRemoteTheme.opacityPercent") private var remoteOpacityPercent = 100

    var body: some View {
        GeometryReader { _ in
            ZStack {
                LinearGradient(
                    colors: [Color(remoteHex: remoteBackground).opacity(0.72 * Self.opacityValue(remoteOpacityPercent)), Color(remoteHex: remoteMuted).opacity(0.18 * Self.opacityValue(remoteOpacityPercent)), Color(remoteHex: remoteBackground).opacity(Self.opacityValue(remoteOpacityPercent))],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        let phase = timeline.date.timeIntervalSinceReferenceDate * 1.35
                        Self.drawConstellation(in: &context, size: size, phase: phase, accent: Color(remoteHex: remoteAccent), muted: Color(remoteHex: remoteMuted), opacity: Self.opacityValue(remoteOpacityPercent))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func opacityValue(_ percent: Int) -> Double { max(0.10, min(1.0, Double(percent) / 100.0)) }
    private static func drawConstellation(in context: inout GraphicsContext, size: CGSize, phase: Double, accent: Color, muted: Color, opacity: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let count = 25
        let points: [CGPoint] = (0..<count).map { index in
            let seed = Double(index)
            let baseX = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
            let baseY = (seed * 0.75487766625 + 0.17).truncatingRemainder(dividingBy: 1)
            let driftX = sin(phase + seed * 1.73) * 0.075
            let driftY = cos(phase * 0.83 + seed * 1.21) * 0.075
            return CGPoint(
                x: CGFloat(min(1, max(0, baseX + driftX))) * size.width,
                y: CGFloat(min(1, max(0, baseY + driftY))) * size.height
            )
        }

        let maxDistance = min(size.width, size.height) * 0.27
        for first in 0..<count {
            for second in (first + 1)..<count {
                let a = points[first]
                let b = points[second]
                let dx = a.x - b.x
                let dy = a.y - b.y
                let distance = hypot(dx, dy)
                guard distance < maxDistance else { continue }
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                let lineOpacity = Double(0.11 * (1 - distance / maxDistance)) * opacity
                context.stroke(path, with: .color(muted.opacity(lineOpacity)), lineWidth: 0.55)
            }
        }

        for (index, point) in points.enumerated() {
            let radius: CGFloat = index.isMultiple(of: 5) ? 2.1 : 1.25
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(accent.opacity((index.isMultiple(of: 4) ? 0.42 : 0.20) * opacity)))
        }
    }
}
struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Image("BrandX")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension Color {
    init(remoteHex: String) {
        let key = "WQRemoteTheme.opacityPercent"
        let percent = UserDefaults.standard.object(forKey: key) == nil ? 100 : UserDefaults.standard.integer(forKey: key)
        self.init(remoteHex: remoteHex, opacity: max(0.10, min(1.0, Double(percent) / 100.0)))
    }

    init(remoteHex: String, opacity: Double) {
        let value = remoteHex.hasPrefix("#") ? String(remoteHex.dropFirst()) : remoteHex
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(.sRGB, red: Double((rgb >> 16) & 0xff) / 255.0, green: Double((rgb >> 8) & 0xff) / 255.0, blue: Double(rgb & 0xff) / 255.0, opacity: opacity)
    }
}
