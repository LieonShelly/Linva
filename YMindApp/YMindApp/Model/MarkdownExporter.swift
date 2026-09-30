import Foundation

/// 整棵逻辑树 → Markdown 大纲（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历。
/// 有子节点的节点（分支）→ 标题（`#`×depth，depth>6 用 `######`）；
/// 无子节点的节点（叶子）→ 内容列表项（不缩进，符号按深度循环 - / * / +）。
/// 根节点恒为标题（即使无子节点）。混合深度树天然正确：分支永远是标题，叶子永远是内容。
enum MarkdownExporter {
    /// 叶子列表符号按深度循环：深度2→`-`、3→`*`、4→`+`、5→`-`…
    private static let leafSymbols = ["-", "*", "+"]

    /// 深度 1 = 中心主题；子节点 +1。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    static func markdown(from document: MindMapDocument) -> String {
        var lines: [String] = []
        walk(document.root, depth: 1, into: &lines)
        return lines.joined(separator: "\n\n") + "\n"
    }

    private static func walk(_ node: Node, depth: Int, into lines: inout [String]) {
        if node.children.isEmpty && depth > 1 {
            // 叶子（非根）→ 内容列表项
            let symbol = leafSymbols[(depth - 2) % leafSymbols.count]
            lines.append("\(symbol) \(collapsedText(node.text))")
        } else {
            // 分支或根 → 标题
            let level = min(max(depth, 1), 6)
            lines.append("\(String(repeating: "#", count: level)) \(collapsedText(node.text))")
        }
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
