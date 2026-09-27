import Foundation

/// 整棵逻辑树 → Markdown 标题层级（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历，深度 d → min(d, 6) 个 `#`。
enum MarkdownExporter {
    /// 深度 1 = 中心主题；子节点 +1；超过 6 仍用 `######`。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    static func markdown(from document: MindMapDocument) -> String {
        var lines: [String] = []
        walk(document.root, depth: 1, into: &lines)
        return lines.joined(separator: "\n\n") + "\n"
    }

    private static func walk(_ node: Node, depth: Int, into lines: inout [String]) {
        let level = min(max(depth, 1), 6)
        lines.append("\(String(repeating: "#", count: level)) \(collapsedText(node.text))")
        for child in node.children {
            walk(child, depth: depth + 1, into: &lines)
        }
    }

    /// 对齐原型 treeToMarkdown：\r\n → \n，按行 trim，去空行，join 空格。
    static func collapsedText(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? "未命名" : collapsed
    }
}
