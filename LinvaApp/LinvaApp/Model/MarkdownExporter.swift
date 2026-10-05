import Foundation

/// 整棵逻辑树 → Markdown 大纲（FR-E2）。
/// 纯函数、与渲染无关：忽略折叠，先序遍历。
/// 标题按「兄弟组」递归判定，而非全局深度：
/// - 根恒为标题。
/// - 对每一组兄弟（同一父节点的直接子）：组内存在任一有子节点 → 整组标题；组内全无子节点 → 整组内容。
/// 标题 `#`×depth（depth>6 用 `######`）；内容为列表项（不缩进，符号按深度循环 - / * / +）。
/// 理由：兄弟节点类型一致（层级不错乱），且深分支不会拉高其他兄弟分支下的浅叶子。

/// 单个图片块：块 id 对应导出后 assets/<id>.png 文件名。
struct MarkdownImage: Equatable {
    let blockId: UUID
    let data: Data
}

/// Markdown 导出结果：正文 + 逐节点图片清单（FR-G5 修订：MD 含图）。
struct MarkdownOutput: Equatable {
    let text: String
    let images: [MarkdownImage]
}

enum MarkdownExporter {
    /// 内容列表符号按深度循环：深度2→`-`、3→`*`、4→`+`、5→`-`…
    private static let leafSymbols = ["-", "*", "+"]

    /// 深度 1 = 中心主题；子节点 +1。
    /// 文案取 `text`：换行/回车压成空格、逐行 trim、空行丢弃；最终为空用「未命名」。
    /// 不输出填色 / 侧 / 折叠等元数据（纯结构文档）。
    /// 无图兼容入口：等于 output(from:).text（字节级一致）。
    static func markdown(from document: MindMapDocument) -> String {
        output(from: document).text
    }

    /// 正文 + 逐节点图片清单（FR-G5 修订：MD 含图）。有图节点行内尾缀引用 assets/<id>.png。
    static func output(from document: MindMapDocument) -> MarkdownOutput {
        var lines: [String] = []
        var images: [MarkdownImage] = []
        var rootLine = "# \(collapsedText(document.root.text))"
        for block in document.root.blocks {
            if case .image(let img) = block.kind {
                rootLine += " ![图片](assets/\(block.id.uuidString).png)"
                images.append(MarkdownImage(blockId: block.id, data: img.data))
            }
        }
        lines.append(rootLine)
        walk(children: document.root.children, depth: 2, into: &lines, images: &images)
        return MarkdownOutput(text: lines.joined(separator: "\n\n") + "\n", images: images)
    }

    /// 递归处理一组兄弟：组内是否有任一分支（有子节点）决定整组是标题还是内容。
    private static func walk(children: [Node], depth: Int, into lines: inout [String], images: inout [MarkdownImage]) {
        let groupHasBranch = children.contains { !$0.children.isEmpty }
        for child in children {
            var content = collapsedText(child.text)
            for block in child.blocks {
                if case .image(let img) = block.kind {
                    content += " ![图片](assets/\(block.id.uuidString).png)"
                    images.append(MarkdownImage(blockId: block.id, data: img.data))
                }
            }
            if groupHasBranch {
                let level = min(max(depth, 1), 6)
                lines.append("\(String(repeating: "#", count: level)) \(content)")
            } else {
                let symbol = leafSymbols[(depth - 2) % leafSymbols.count]
                lines.append("\(symbol) \(content)")
            }
            walk(children: child.children, depth: depth + 1, into: &lines, images: &images)
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
