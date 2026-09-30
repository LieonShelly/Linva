import Foundation

/// 整棵逻辑树 → Markdown 大纲（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历。
/// 深度 d ≤ titleDepth 的节点 → 标题（`#`×d，d>6 用 `######`）；
/// 深度 > titleDepth 的节点 → 正文列表项（缩进 `(d - titleDepth)*2` 空格 + `- `）。
/// titleDepth = min(max(整树最大深度 - 1, 1), 3)：树越浅标题越少，长段落下沉为正文。
enum MarkdownExporter {
    /// 深度 1 = 中心主题；子节点 +1。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    static func markdown(from document: MindMapDocument) -> String {
        let titleDepth = min(max(maxDepth(of: document.root) - 1, 1), 3)
        var lines: [String] = []
        walk(document.root, depth: 1, titleDepth: titleDepth, into: &lines)
        return lines.joined(separator: "\n\n") + "\n"
    }

    /// 节点所在子树的深度（root 深度为 1）。
    private static func maxDepth(of node: Node) -> Int {
        var depth = 1
        for child in node.children {
            depth = max(depth, maxDepth(of: child) + 1)
        }
        return depth
    }

    private static func walk(_ node: Node, depth: Int, titleDepth: Int, into lines: inout [String]) {
        if depth <= titleDepth {
            let level = min(max(depth, 1), 6)
            lines.append("\(String(repeating: "#", count: level)) \(collapsedText(node.text))")
        } else {
            let indent = String(repeating: " ", count: (depth - titleDepth - 1) * 2)
            lines.append("\(indent)- \(collapsedText(node.text))")
        }
        for child in node.children {
            walk(child, depth: depth + 1, titleDepth: titleDepth, into: &lines)
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
