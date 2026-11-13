import SwiftUI

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VnuaFont.font(.headline, .medium))
            .frame(maxWidth: .infinity, minHeight: Metrics.minTap)
            .padding(.horizontal, 16)
            .foregroundStyle(Palette.onAccent)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VnuaFont.font(.headline, .medium))
            .frame(maxWidth: .infinity, minHeight: Metrics.minTap)
            .padding(.horizontal, 16)
            .foregroundStyle(Palette.text)
            .background(configuration.isPressed ? Palette.neutralFill : Palette.surface,
                        in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Palette.divider, lineWidth: 1))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var vnuaPrimary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var vnuaSecondary: SecondaryButtonStyle { .init() } }

// MARK: - Card

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radiusLarge, style: .continuous)
                .strokeBorder(Palette.divider, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Badge

struct Badge: View {
    enum Tone { case neutral, accent, success, warning }
    let text: String
    var systemImage: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(VnuaFont.font(.caption, .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
    }

    private var fg: Color {
        switch tone {
        case .neutral: return Palette.secondaryText
        case .accent: return Palette.accent
        case .success: return Palette.success
        case .warning: return Palette.warning
        }
    }
    private var bg: Color {
        switch tone {
        case .neutral: return Palette.neutralFill
        case .accent: return Palette.accentSoft
        case .success: return Palette.successSoft
        case .warning: return Palette.warningSoft
        }
    }
}

// MARK: - Club monogram

struct ClubMonogram: View {
    let club: Club
    var size: CGFloat = 48

    var body: some View {
        Text(club.monogram)
            .font(VnuaFont.fixed(size: size * 0.38, .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: club.accentHex), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(VnuaFont.font(.caption, .medium))
            .tracking(0.8)
            .foregroundStyle(Palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Toast banner

struct BannerView: View {
    let banner: Banner
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(banner.message).font(VnuaFont.font(.subheadline, .medium))
        }
        .foregroundStyle(banner.isError ? Palette.danger : Palette.success)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Metrics.gutter)
        .accessibilityElement(children: .combine)
    }
}
