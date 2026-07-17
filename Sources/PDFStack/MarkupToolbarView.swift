import SwiftUI

struct MarkupToolbarView: View {
    @ObservedObject var session: MarkupSession
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(MarkupTool.allCases.enumerated()), id: \.offset) { index, tool in
                if index > 0, tool.group != MarkupTool.allCases[index - 1].group {
                    Rectangle()
                        .fill(Pheno.border08)
                        .frame(width: 1, height: 30)
                        .padding(.horizontal, 5)
                }
                ToolTile(
                    tool: tool,
                    isActive: session.activeTool == tool,
                    action: { session.activeTool = tool }
                )
            }
            Spacer()
            saveButton
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Pheno.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Pheno.border06).frame(height: 1)
        }
    }

    private var saveButton: some View {
        Button(action: onSave) {
            HStack(spacing: 7) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15))
                Text("Save")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Pheno.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ToolTile: View {
    let tool: MarkupTool
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 16))
                Text(tool.label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
            }
            .foregroundColor(foreground)
            .padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9))
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        if isActive { return .white }
        if isHovering { return Pheno.textHigh }
        return Pheno.textMid
    }

    private var background: Color {
        if isActive { return Pheno.accent }
        if isHovering { return Pheno.elevated }
        return .clear
    }
}
