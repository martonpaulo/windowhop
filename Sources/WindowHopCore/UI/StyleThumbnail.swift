import SwiftUI
import WindowHopKit

/// A miniature switcher panel in each style, so the two options read apart
/// without their labels (#124): three coloured app icons, or three small
/// windows with an app badge in the corner. The middle tile is selected, drawn
/// as the real panel draws it.
struct StyleThumbnail: View {
    let mode: AppearanceMode

    /// One colour and glyph per miniature app, shared by the icons and the
    /// preview badges so both drawings show the same three apps.
    private static let apps: [(color: Color, symbol: String)] = [
        (.blue, "globe"), (.orange, "note.text"), (.gray, "terminal.fill"),
    ]

    var body: some View {
        HStack(spacing: DesignTokens.settingsStyleThumbnailItemSpacing) {
            ForEach(Self.apps.indices, id: \.self) { index in
                tile(index: index)
                    .padding(DesignTokens.settingsStyleThumbnailSelectionPadding)
                    .background(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.settingsStyleThumbnailSelectionCornerRadius
                        )
                        .fill(index == 1 ? selectionFill : .clear))
            }
        }
        .frame(
            width: DesignTokens.settingsStyleThumbnailWidth,
            height: DesignTokens.settingsStyleThumbnailHeight
        )
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailCornerRadius)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailCornerRadius)
                .strokeBorder(.separator)
        )
        .accessibilityHidden(true)
    }

    /// The real panel's selection: a neutral plate behind an icon, an accent
    /// plate behind a preview.
    private var selectionFill: Color {
        mode == .appIcons ? Color.primary.opacity(0.14) : Color.accentColor.opacity(0.78)
    }

    @ViewBuilder
    private func tile(index: Int) -> some View {
        switch mode {
        case .appIcons:
            appIcon(index: index, size: DesignTokens.settingsStyleThumbnailIconSize)
        case .windowPreviews:
            miniWindow
                .overlay(alignment: .bottomTrailing) {
                    appIcon(index: index, size: DesignTokens.settingsStyleThumbnailBadgeSize)
                        .offset(
                            x: DesignTokens.settingsStyleThumbnailBadgeOverlap,
                            y: DesignTokens.settingsStyleThumbnailBadgeOverlap)
                }
        }
    }

    private func appIcon(index: Int, size: CGFloat) -> some View {
        let app = Self.apps[index]
        let radius =
            size == DesignTokens.settingsStyleThumbnailIconSize
            ? DesignTokens.settingsStyleThumbnailIconCornerRadius
            : DesignTokens.settingsStyleThumbnailBadgeCornerRadius
        return RoundedRectangle(cornerRadius: radius)
            .fill(app.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: app.symbol)
                    .font(
                        .system(
                            size: size * DesignTokens.settingsStyleThumbnailGlyphSize
                                / DesignTokens.settingsStyleThumbnailIconSize,
                            weight: .semibold)
                    )
                    .foregroundStyle(.white)
            }
    }

    private var miniWindow: some View {
        let buttonColors: [Color] = [.red, .yellow, .green]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.settingsStyleThumbnailWindowButtonSpacing) {
                ForEach(buttonColors.indices, id: \.self) { index in
                    Circle()
                        .fill(buttonColors[index].opacity(0.85))
                        .frame(
                            width: DesignTokens.settingsStyleThumbnailWindowButtonSize,
                            height: DesignTokens.settingsStyleThumbnailWindowButtonSize)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.settingsStyleThumbnailContentInset)
            .frame(height: DesignTokens.settingsStyleThumbnailTitleBarHeight)
            .background(Color.secondary.opacity(0.18))
            VStack(alignment: .leading, spacing: DesignTokens.settingsStyleThumbnailLineSpacing) {
                ForEach(DesignTokens.settingsStyleThumbnailLineFractions.indices, id: \.self) { line in
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(
                            width: (DesignTokens.settingsStyleThumbnailPreviewWidth
                                - DesignTokens.settingsStyleThumbnailContentInset * 2)
                                * DesignTokens.settingsStyleThumbnailLineFractions[line],
                            height: DesignTokens.settingsStyleThumbnailLineHeight)
                }
            }
            .padding(DesignTokens.settingsStyleThumbnailContentInset)
            Spacer(minLength: 0)
        }
        .frame(
            width: DesignTokens.settingsStyleThumbnailPreviewWidth,
            height: DesignTokens.settingsStyleThumbnailPreviewHeight
        )
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.settingsStyleThumbnailPreviewCornerRadius))
    }
}
