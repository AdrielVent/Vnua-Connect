import SwiftUI
import UIKit

// MARK: - Color tokens
// Ported from src/vnua.css ("warm editorial campus community"), plus dark-mode values.
// Every token is dynamic, so light/dark switch automatically (HIG: support Dark Mode).

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }

    static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Palette {
    static let ground        = Color.dynamic("#eef1f5", "#070b14")
    static let background    = Color.dynamic("#f6f7f9", "#0b1220")
    static let surface       = Color.dynamic("#ffffff", "#141c2c")
    static let text          = Color.dynamic("#101828", "#eef2f8")
    static let secondaryText = Color.dynamic("#4b5565", "#a3aec2")
    static let divider       = Color.dynamic("#e1e5eb", "#263045")
    static let neutralFill   = Color.dynamic("#eef1f5", "#1c2538")
    static let accent        = Color.dynamic("#1a3d6d", "#8db7e6")
    static let onAccent      = Color.dynamic("#ffffff", "#0b1220")
    static let accentSoft    = Color.dynamic("#e7eef7", "#16233a")
    static let success       = Color.dynamic("#24704f", "#7fd1a8")
    static let successSoft   = Color.dynamic("#e3f1ea", "#12291f")
    static let warning       = Color.dynamic("#8a4b06", "#f2b86b")
    static let warningSoft   = Color.dynamic("#fbeedc", "#2e2212")
    /// SHPE orange — small highlights only (too light for text on white).
    static let highlight     = Color.dynamic("#fd652f", "#ff8a5c")
    static let danger        = Color.dynamic("#b42318", "#ff9c8a")
}

enum Metrics {
    static let gutter: CGFloat = 16
    static let radiusSmall: CGFloat = 8
    static let radius: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    /// HIG minimum hit target.
    static let minTap: CGFloat = 44
}

// MARK: - Typography
// Brand font: Circular (Lineto). It is commercial: buy a license that covers app embedding,
// then drop the .otf/.ttf files into VnuaConnect/Resources/Fonts. FontRegistrar loads them at
// launch and every style below switches to Circular automatically. Until then we fall back to
// SF Pro, Apple's system font. Every style scales with Dynamic Type (relativeTo:).

enum VnuaFont {
    enum Weight { case regular, medium, bold, black }

    /// Brand fonts found in the bundle, keyed by weight. Filled by FontRegistrar at launch from each file's
    /// real family name and weight, so any Circular file naming works (lineto-circular-book.ttf, CircularStd-Bold.otf…).
    /// A weight is only filled by a file that's actually close to it, so a lone Black file never ends up as body text.
    nonisolated(unsafe) fileprivate(set) static var resolved: [Weight: String] = [:]

    static var isUsingBrandFont: Bool { !resolved.isEmpty }

    /// Big display text (screen titles, page headers) uses Circular Black when it's installed.
    private static let displayStyles: Set<Font.TextStyle> = [.largeTitle, .title, .title2]

    private static func name(for style: Font.TextStyle?, _ weight: Weight) -> String? {
        if weight == .bold, let style, displayStyles.contains(style), let black = resolved[.black] { return black }
        return resolved[weight]
    }

    static func font(_ style: Font.TextStyle, _ weight: Weight = .regular) -> Font {
        if let name = name(for: style, weight) {
            return .custom(name, size: baseSize(style), relativeTo: style)
        }
        return .system(style, design: .default, weight: systemWeight(weight))
    }

    /// Fixed-size text that should not scale (monograms).
    static func fixed(size: CGFloat, _ weight: Weight = .regular) -> Font {
        if let name = resolved[weight] ?? (weight == .bold ? resolved[.black] : nil) { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: systemWeight(weight))
    }

    static func uiFont(_ style: UIFont.TextStyle, _ weight: Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let swiftUIStyle: Font.TextStyle? = style == .largeTitle ? .largeTitle : style == .title1 ? .title : nil
        if let name = name(for: swiftUIStyle, weight), let f = UIFont(name: name, size: base.pointSize) {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: f)
        }
        let w: UIFont.Weight = weight == .black ? .heavy : weight == .bold ? .bold : weight == .medium ? .semibold : .regular
        return UIFont.systemFont(ofSize: base.pointSize, weight: w)
    }

    private static func systemWeight(_ w: Weight) -> Font.Weight {
        switch w {
        case .regular: return .regular
        case .medium: return .semibold
        case .bold: return .bold
        case .black: return .heavy
        }
    }

    /// Default (Large) Dynamic Type sizes from the HIG typography table.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }
}

enum FontRegistrar {
    /// Registers every bundled .otf/.ttf and picks the closest Circular file for each weight we use.
    static func registerBundledFonts() {
        let urls = ["otf", "ttf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        var found: [(name: String, weight: CGFloat)] = []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
            for d in descriptors {
                let family = (CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String) ?? ""
                guard family.localizedCaseInsensitiveContains("circular"),
                      let name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String,
                      !name.localizedCaseInsensitiveContains("italic") else { continue }
                let font = CTFontCreateWithName(name as CFString, 12, nil)
                let traits = CTFontCopyTraits(font) as NSDictionary
                let w = (traits[kCTFontWeightTrait] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
                found.append((name, w))
            }
        }
        guard !found.isEmpty else { return }
        // Target weights on Core Text's −1…1 scale: Book ≈ 0, Medium ≈ 0.23, Bold ≈ 0.4, Black ≈ 0.8.
        // Only accept a file within 0.15 of the target; otherwise that weight stays SF Pro.
        let targets: [(VnuaFont.Weight, CGFloat)] = [(.regular, 0), (.medium, 0.23), (.bold, 0.4), (.black, 0.8)]
        var out: [VnuaFont.Weight: String] = [:]
        for (weight, target) in targets {
            if let best = found.min(by: { abs($0.weight - target) < abs($1.weight - target) }),
               abs(best.weight - target) <= 0.15 {
                out[weight] = best.name
            }
        }
        VnuaFont.resolved = out
    }

    /// Which Circular files ended up in use, for the Profile screen.
    static var summary: String {
        VnuaFont.resolved.isEmpty ? "SF Pro (Circular not installed)"
            : Set(VnuaFont.resolved.values).sorted().joined(separator: ", ")
              + (VnuaFont.resolved[.regular] == nil ? " + SF Pro for text" : "")
    }

    /// Navigation bar titles use the brand font too.
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.largeTitleTextAttributes = [.font: VnuaFont.uiFont(.largeTitle, .bold), .foregroundColor: UIColor(Palette.text)]
        nav.titleTextAttributes = [.font: VnuaFont.uiFont(.headline, .medium), .foregroundColor: UIColor(Palette.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let scroll = UINavigationBarAppearance()
        scroll.configureWithTransparentBackground()
        scroll.largeTitleTextAttributes = nav.largeTitleTextAttributes
        scroll.titleTextAttributes = nav.titleTextAttributes
        UINavigationBar.appearance().scrollEdgeAppearance = scroll
    }
}
