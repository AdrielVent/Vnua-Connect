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
    static let ground        = Color.dynamic("#efe9df", "#12100d")
    static let background    = Color.dynamic("#f8f4ec", "#1a1713")
    static let surface       = Color.dynamic("#fffdf9", "#24201b")
    static let text          = Color.dynamic("#1f1b16", "#f3ede3")
    static let secondaryText = Color.dynamic("#5f5446", "#b9ac98")
    static let divider       = Color.dynamic("#e2d9cb", "#3a332b")
    static let neutralFill   = Color.dynamic("#ece4d7", "#332d26")
    static let accent        = Color.dynamic("#7a321d", "#e2ae98")
    static let onAccent      = Color.dynamic("#ffffff", "#1f1b16")
    static let accentSoft    = Color.dynamic("#f8e9e2", "#3b241b")
    static let success       = Color.dynamic("#2f5d3a", "#8fc79b")
    static let successSoft   = Color.dynamic("#e3efe5", "#1f3324")
    static let warning       = Color.dynamic("#7a4f12", "#e0b35c")
    static let warningSoft   = Color.dynamic("#f6ead3", "#3a2e17")
    static let danger        = Color.dynamic("#a2472b", "#f0a58a")
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
    enum Weight { case regular, medium, bold }

    /// Brand fonts found in the bundle, keyed by weight. Filled by FontRegistrar at launch from each file's
    /// real family name and weight, so any Circular file naming works (lineto-circular-book.ttf, CircularStd-Bold.otf…).
    nonisolated(unsafe) fileprivate(set) static var resolved: [Weight: String] = [:]

    static var isUsingBrandFont: Bool { resolved[.regular] != nil }

    static func font(_ style: Font.TextStyle, _ weight: Weight = .regular) -> Font {
        if let name = resolved[weight] ?? resolved[.regular] {
            return .custom(name, size: baseSize(style), relativeTo: style)
        }
        return .system(style, design: .default, weight: systemWeight(weight))
    }

    /// Fixed-size text that should not scale (monograms, QR captions).
    static func fixed(size: CGFloat, _ weight: Weight = .regular) -> Font {
        if let name = resolved[weight] ?? resolved[.regular] { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: systemWeight(weight))
    }

    static func uiFont(_ style: UIFont.TextStyle, _ weight: Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        if let name = resolved[weight], let f = UIFont(name: name, size: base.pointSize) {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: f)
        }
        return UIFont.systemFont(ofSize: base.pointSize, weight: weight == .bold ? .bold : weight == .medium ? .semibold : .regular)
    }

    private static func systemWeight(_ w: Weight) -> Font.Weight {
        switch w {
        case .regular: return .regular
        case .medium: return .semibold
        case .bold: return .bold
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
        // Target weights on Core Text's −1…1 scale: Book ≈ 0, Medium ≈ 0.23, Bold ≈ 0.4.
        func closest(_ target: CGFloat) -> String {
            found.min { abs($0.weight - target) < abs($1.weight - target) }!.name
        }
        VnuaFont.resolved = [.regular: closest(0), .medium: closest(0.23), .bold: closest(0.4)]
    }

    /// Which Circular files ended up in use, for the Profile screen.
    static var summary: String {
        VnuaFont.resolved.isEmpty ? "SF Pro (Circular not installed)"
            : Set(VnuaFont.resolved.values).sorted().joined(separator: ", ")
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
