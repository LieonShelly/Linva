import SwiftUI

/// 导入预览浮层：展示解析出的树（缩进列表），确认/取消。
struct ImportPreviewView: View {
    let sourceName: String
    let nodeCount: Int
    let depth: Int
    let document: MindMapDocument
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入预览")
                .font(.headline)
            Text("\(sourceName) · \(nodeCount) 个节点 · \(depth) 层")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView {
                IndentNodeView(node: document.root, depth: 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("确认导入") { onConfirm() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

/// 递归缩进行：一个节点一行，子节点按层缩进（`Node` 是 `Identifiable`）。
private struct IndentNodeView: View {
    let node: Node
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(String(repeating: " ", count: depth * 2) + (depth == 0 ? "◎ " : "–"))
                Text(node.text)
            }
            ForEach(node.children, id: \.id) { child in
                IndentNodeView(node: child, depth: depth + 1)
            }
        }
    }
}