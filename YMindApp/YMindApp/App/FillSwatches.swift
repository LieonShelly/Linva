import SwiftUI

/// 工具条填色色点组：5 色 + 默认清除（斜线）。
struct FillSwatchesView: View {
    let canSetFill: Bool
    let activeFill: NodeFill?
    let fillActive: Bool
    let setFill: (NodeFill?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NodeFill.allCases, id: \.self) { fill in
                swatchButton(
                    color: Color(nsColor: NodeFillStyle.swatch(fill)),
                    isActive: fillActive && activeFill == fill,
                    help: "填色 \(fill.rawValue)",
                    action: { setFill(fill) }
                )
            }
            // 默认清除点：圆形底 + 对角斜线（对齐原型 .swatch-none）
            swatchButton(
                color: Color(nsColor: .controlBackgroundColor),
                isActive: fillActive && activeFill == nil,
                help: "清除填色",
                action: { setFill(nil) }
            )
        }
    }

    private func swatchButton(
        color: Color,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                SlashLine()
                    .stroke(Color(red: 0.607, green: 0.239, blue: 0.180), lineWidth: 1.5)
                    .frame(width: 9, height: 9)
            }
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(
                        isActive ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: isActive ? 2 : 1
                    )
                    .padding(-3)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSetFill)
        .help(help)
    }
}

/// 对角斜线（默认清除点用）。
private struct SlashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}
