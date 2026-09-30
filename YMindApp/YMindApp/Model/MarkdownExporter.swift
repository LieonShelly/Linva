import Foundation

/// 整棵逻辑树 → Markdown 大纲（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历。
/// 标题按「兄弟组」递归判定，而非全局深度：
/// - 根恒为标题。
/// - 对每一组兄弟（同一父节点的直接子）：组内存在任一有子节点 → 整组标题；组内全无子节点 → 整组内容。
/// 标题 `#`×depth（depth>6 用 `######`）；内容为列表项（不缩进，符号按深度循环 - / * / +）。
/// 理由：兄弟节点类型一致（层级不错乱），且深分支不会拉高其他兄弟分支下的浅叶子。
enum MarkdownExporter {
    /// 内容列表符号按深度循环：深度2→`-`、3→`*`、4→`+`、5→`-`…
    private static let leafSymbols = ["-", "*", "+"]

    /// 深度 1 = 中心主题；子节点 +1。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    static func markdown(from document: MindMapDocument) -> String {
        var lines: [String] = []
        lines.append("# \(collapsedText(document.root.text))")
        walk(children: document.root.children, depth: 2, into: &lines)
        return lines.joined(separator: "\n\n") + "\n"
    }

    /// 递归处理一组兄弟：组内是否有任一分支（有子节点）决定整组是标题还是内容。
    private static func walk(children: [Node], depth: Int, into lines: inout [String]) {
        let groupHasBranch = children.contains { !$0.children.isEmpty }
        for child in children {
            if groupHasBranch {
                let level = min(max(depth, 1), 6)
                lines.append("\(String(repeating: "#", count: level)) \(collapsedText(child.text))")
            } else {
                let symbol = leafSymbols[(depth - 2) % leafSymbols.count]
                lines.append("\(symbol) \(collapsedText(child.text))")
            }
            walk(children: child.children, depth: depth + 1, into: &lines)
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
