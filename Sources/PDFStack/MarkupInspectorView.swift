import AppKit
import PDFKit
import PDFStackKit
import SwiftUI

struct MarkupInspectorView: View {
    @ObservedObject var session: MarkupSession
    let onSelect: (AnnotationEntry) -> Void
    let onCancel: () -> Void
    let onDone: () -> Void
    /// Commits the open on-page text edit (wired to the "Done editing" button).
    var onCommitInline: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            styleSection
            annotationsSection
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Pheno.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(Pheno.border06).frame(width: 1)
        }
    }

    // MARK: - Style section

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isTextTool {
                textStyleSection
            } else {
                EyebrowLabel("\(session.activeTool.label) Style")

                swatchRow
                    .padding(.top, 12)

                if isOpacityTool {
                    opacityRow
                        .padding(.top, 16)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Pheno.border06).frame(height: 1)
        }
    }

    private var isTextTool: Bool {
        session.activeTool == .text || session.activeTool == .editText
    }

    // MARK: - Text style section

    private static let fontChoices: [(label: String, name: String?)] = [
        ("System", nil),
        ("Helvetica", "Helvetica"),
        ("Times New Roman", "Times New Roman"),
        ("Courier New", "Courier New"),
        ("Georgia", "Georgia"),
        ("Verdana", "Verdana"),
    ]

    private var textStyleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EyebrowLabel("Text Style")
            fontRow
            sizeRow
            textColorRow
            alignmentRow
            if session.inlineEdit != nil {
                doneEditingButton
            }
        }
    }

    private var currentFontLabel: String {
        Self.fontChoices.first { $0.name == session.textStyle.fontName }?.label ?? "System"
    }

    private var fontRow: some View {
        Menu {
            ForEach(Self.fontChoices, id: \.label) { choice in
                Button(choice.label) {
                    session.mutateTextStyle { $0.fontName = choice.name }
                }
            }
        } label: {
            HStack {
                Text(currentFontLabel)
                    .font(.system(size: 12.5))
                    .foregroundColor(Pheno.textValue)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(Pheno.textDim)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Pheno.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { Double(session.textStyle.fontSize) },
            set: { newValue in
                session.mutateTextStyle { $0.fontSize = min(96, max(6, CGFloat(newValue))) }
            }
        )
    }

    private var sizeRow: some View {
        HStack(spacing: 8) {
            sizeStep("minus") {
                session.mutateTextStyle { $0.fontSize = max(6, $0.fontSize - 1) }
            }
            TextField("", value: sizeBinding, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundColor(Pheno.textValue)
                .frame(width: 40, height: 24)
                .background(Pheno.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            sizeStep("plus") {
                session.mutateTextStyle { $0.fontSize = min(96, $0.fontSize + 1) }
            }
            Spacer()
        }
    }

    private func sizeStep(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Pheno.textValue)
                .frame(width: 24, height: 24)
                .background(Pheno.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var textColorRow: some View {
        HStack(spacing: 10) {
            ForEach(textColorChoices, id: \.id) { choice in
                Button {
                    session.mutateTextStyle { $0.color = choice.nsColor }
                } label: {
                    textColorCircle(choice.color, selected: isSelectedColor(choice.nsColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.id)
            }
        }
    }

    private var textColorChoices: [(id: String, color: Color, nsColor: NSColor)] {
        Pheno.swatches.map { ($0.id, $0.color, $0.nsColor) }
            + [("black", .black, .black), ("white", .white, .white)]
    }

    @ViewBuilder
    private func textColorCircle(_ color: Color, selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle()
                    .stroke(Pheno.textHigh, lineWidth: 2)
                    .frame(width: 30, height: 30)
            }
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
        }
        .frame(width: 30, height: 30)
    }

    private func isSelectedColor(_ nsColor: NSColor) -> Bool {
        guard let a = session.textStyle.color.usingColorSpace(.sRGB),
              let b = nsColor.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }

    private var alignmentRow: some View {
        HStack(spacing: 8) {
            alignmentToggle(.left, "text.alignleft")
            alignmentToggle(.center, "text.aligncenter")
            alignmentToggle(.right, "text.alignright")
            Spacer()
        }
    }

    private func alignmentToggle(_ alignment: NSTextAlignment, _ symbol: String) -> some View {
        // .natural (used when a detected block is edited) reads as left.
        let isActive = session.textStyle.alignment == alignment
            || (alignment == .left && session.textStyle.alignment == .natural)
        return Button {
            session.mutateTextStyle { $0.alignment = alignment }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(isActive ? .white : Pheno.textMid)
                .frame(width: 34, height: 30)
                .background(isActive ? Pheno.accent : Pheno.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var doneEditingButton: some View {
        Button(action: onCommitInline) {
            Text("Done editing")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Pheno.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var swatchRow: some View {
        HStack(spacing: 10) {
            ForEach(Pheno.swatches) { swatch in
                Button {
                    session.activeSwatchID = swatch.id
                } label: {
                    swatchCircle(swatch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(session.activeSwatchID == swatch.id ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder
    private func swatchCircle(_ swatch: Pheno.Swatch) -> some View {
        let selected = session.activeSwatchID == swatch.id
        ZStack {
            if selected {
                Circle()
                    .stroke(Pheno.textHigh, lineWidth: 2)
                    .frame(width: 30, height: 30)
            }
            Circle()
                .fill(swatch.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(width: 30, height: 30)
    }

    private var isOpacityTool: Bool {
        switch session.activeTool {
        case .highlight, .underline, .strike: return true
        default: return false
        }
    }

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Opacity")
                    .font(.system(size: 11.5))
                    .foregroundColor(Pheno.textMid)
                Spacer()
                Text("\(Int((session.opacity * 100).rounded()))%")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundColor(Pheno.textValue)
            }
            OpacitySlider(value: $session.opacity)
        }
    }

    // MARK: - Annotations section

    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel("Annotations")
                Spacer()
                Text("\(session.annotations.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Pheno.accentBright)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 8)
                    .background(Pheno.accentBright.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 8, trailing: 16))

            ScrollView {
                annotationRows
            }
        }
    }

    private var annotationRows: some View {
        LazyVStack(spacing: 6) {
            ForEach(session.annotations) { entry in
                AnnotationRow(
                    entry: entry,
                    isSelected: session.selectedAnnotationID == entry.id
                ) {
                    session.selectedAnnotationID = entry.id
                    onSelect(entry)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Pheno.textValue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Pheno.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Pheno.lightButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Pheno.lightButtonBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .overlay(alignment: .top) {
            Rectangle().fill(Pheno.border06).frame(height: 1)
        }
    }
}

private struct AnnotationRow: View {
    let entry: AnnotationEntry
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            indicator
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Pheno.rowTitle)
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Pheno.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var indicator: some View {
        if entry.isSquareIndicator {
            RoundedRectangle(cornerRadius: 2)
                .fill(Pheno.accentBright)
                .frame(width: 9, height: 9)
        } else {
            Circle()
                .fill(Color(entry.indicatorColor))
                .frame(width: 9, height: 9)
        }
    }

    private var rowBackground: Color {
        if isSelected || isHovering { return Pheno.selectedRow }
        return .clear
    }
}

/// Custom opacity slider: 5pt track, accentBright fill, 13pt light thumb,
/// draggable across the full width.
private struct OpacitySlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = max(0, min(1, value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Pheno.elevated)
                    .frame(height: 5)
                Capsule()
                    .fill(Pheno.accentBright)
                    .frame(width: width * fraction, height: 5)
                Circle()
                    .fill(Pheno.textHigh)
                    .frame(width: 13, height: 13)
                    .shadow(color: Color.black.opacity(0.5), radius: 1.5, x: 0, y: 1)
                    .offset(x: (width - 13) * fraction)
            }
            .frame(height: 13)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = max(0, min(width, g.location.x))
                        value = width > 0 ? Double(x / width) : 0
                    }
            )
        }
        .frame(height: 13)
    }
}
