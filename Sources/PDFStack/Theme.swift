import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

enum Pheno {
    // Chrome
    static let chromeDeep = Color(hex: 0x0E1319)
    static let panel = Color(hex: 0x12171D)
    static let canvasBg = Color(hex: 0x0A0E12)
    static let elevated = Color(hex: 0x232B34)
    static let selectedRow = Color(hex: 0x1C242D)

    // Accent
    static let accent = Color(hex: 0x1B6A9C)
    static let accentBright = Color(hex: 0x3F91BC)

    // Text
    static let textHigh = Color(hex: 0xEAEEF2)
    static let textMid = Color(hex: 0x9AA6B1)
    static let textDim = Color(hex: 0x7F8A95)
    static let textEyebrow = Color(hex: 0x6B7681)
    static let textValue = Color(hex: 0xC3CCD4)
    static let rowTitle = Color(hex: 0xD3DAE0)

    // Light button
    static let lightButtonBg = Color(hex: 0xEAEEF2)
    static let lightButtonText = Color(hex: 0x0E1319)

    // Status
    static let pink = Color(hex: 0xE4506B)
    static let green = Color(hex: 0x46A36A)

    // Hairline borders
    static let border06 = Color.white.opacity(0.06)
    static let border07 = Color.white.opacity(0.07)
    static let border08 = Color.white.opacity(0.08)

    struct Swatch: Identifiable {
        let id: String
        let name: String
        let nsColor: NSColor
        let color: Color
    }

    // Single table so SwiftUI rings and PDFAnnotation colors share one source.
    static let swatches: [Swatch] = [
        Swatch(id: "yellow", name: "Yellow", nsColor: NSColor(hex: 0xF2C94C), color: Color(hex: 0xF2C94C)),
        Swatch(id: "green", name: "Green", nsColor: NSColor(hex: 0x46A36A), color: Color(hex: 0x46A36A)),
        Swatch(id: "pink", name: "Pink", nsColor: NSColor(hex: 0xE4506B), color: Color(hex: 0xE4506B)),
        Swatch(id: "blue", name: "Blue", nsColor: NSColor(hex: 0x3F91BC), color: Color(hex: 0x3F91BC)),
        Swatch(id: "orange", name: "Orange", nsColor: NSColor(hex: 0xE08A2B), color: Color(hex: 0xE08A2B)),
    ]
}

struct EyebrowLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(11 * 0.13) // 0.13em at 11pt
            .foregroundColor(Pheno.textEyebrow)
    }
}

/// Icon-only chrome button (e.g. the sidebar "add PDFs" plus): textMid, lightens
/// to elevated on hover, never resizes.
struct PhenoIconButton: View {
    let systemName: String
    var accessibilityLabel: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Pheno.textMid)
                .frame(width: 24, height: 24)
                .background(isHovering ? Pheno.elevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Primary accent button used for "commit" actions (Save, Add PDFs). Accent fill,
/// white 12.5 semibold, optional leading icon.
struct PhenoAccentButton: View {
    let title: String
    var systemImage: String?
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 34)
            .background(Pheno.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Text tool-tile button for the page-grid mode row (Trim/Split/Pages/Markup):
/// textMid default, lightens to elevated + textHigh on hover, dims when disabled.
struct PhenoModeButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(disabled ? Pheno.textMid : (isHovering ? Pheno.textHigh : Pheno.textMid))
                .padding(EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11))
                .background((isHovering && !disabled) ? Pheno.elevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }
}

enum PhenoActionKind {
    case secondary
    case destructive
    case primary
}

/// Footer action button (Cancel/Apply/Delete/etc). Secondary = elevated fill with
/// textValue, destructive = pink text on elevated, primary = accent fill white.
struct PhenoActionButton: View {
    let title: String
    var kind: PhenoActionKind = .secondary
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: kind == .primary ? .semibold : .medium))
                .foregroundColor(foreground)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .secondary: return Pheno.textValue
        case .destructive: return Pheno.pink
        case .primary: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .secondary, .destructive: return Pheno.elevated
        case .primary: return Pheno.accent
        }
    }
}
