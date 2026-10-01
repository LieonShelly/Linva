import AppKit
import CoreText

/// 块序测量结果：节点总尺寸 + 逐块布局（rect 为节点局部坐标 top-left 原点）。
struct BlockMeasure {
    let size: NodeSize
    let blocks: [BlockLayoutFrame]
}

struct TextMeasure {
    func size(for node: Node, isRoot: Bool) -> NodeSize {
        measure(for: node, isRoot: isRoot).size
    }

    /// 块序尺寸合成：按块序叠加——文本块累行高、图片块累图高，块间 imageTextGap，末块后无 gap。
    /// 锚点对齐旧观感：文本块顶部留 verticalPadding（旧 TextAtlas 整盒内 textRect.y 语义），
    /// 图片块贴顶（旧 imageRect y=0 语义），节点底部统一留 verticalPadding。
    func measure(for node: Node, isRoot: Bool) -> BlockMeasure {
        let font = NSFont.systemFont(
            ofSize: isRoot ? 18.4 : 14.7,
            weight: isRoot ? .bold : .medium
        )
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth = isRoot
            ? LayoutConstants.rootMaxTextWidth
            : LayoutConstants.nodeMaxTextWidth

        let horizontalPadding = isRoot ? LayoutConstants.rootPadX : LayoutConstants.nodePadX
        let verticalPadding = isRoot ? LayoutConstants.rootPadY : LayoutConstants.nodePadY
        let lineHeight = isRoot ? LayoutConstants.rootLineHeight : LayoutConstants.nodeLineHeight

        var blocks: [BlockLayoutFrame] = []
        var maxBlockWidth: CGFloat = 0
        var contentHeight: CGFloat = 0

        for block in node.blocks {
            switch block.kind {
            case .text(let s):
                let measured = measureTextWidth(s, maxWidth: maxWidth, attributes: attributes)
                let lines = lineCount(s, maxWidth: maxWidth, attributes: attributes)
                let width = ceil(measured + horizontalPadding * 2)
                let height = ceil(CGFloat(lines) * lineHeight)
                maxBlockWidth = max(maxBlockWidth, width)
                // 文本顶 = 分配槽顶 + verticalPadding（旧 TextAtlas 整盒内 textRect.y=verticalPadding）
                let y = contentHeight + verticalPadding
                blocks.append(BlockLayoutFrame(
                    blockId: block.id,
                    text: s,
                    rect: CGRect(x: 0, y: y, width: width, height: height)
                ))
                contentHeight = y + height
            case .image(let img):
                guard img.pixelSize.width > 0, img.pixelSize.height > 0 else { continue }
                let width = min(CGFloat(img.pixelSize.width), LayoutConstants.imageMaxDisplayWidth)
                let height = width * CGFloat(img.pixelSize.height) / CGFloat(img.pixelSize.width)
                maxBlockWidth = max(maxBlockWidth, width + horizontalPadding * 2)
                // 图片贴顶（旧 imageRect y=0，无 padding）
                blocks.append(BlockLayoutFrame(
                    blockId: block.id,
                    text: nil,
                    rect: CGRect(x: 0, y: contentHeight, width: width, height: height)
                ))
                contentHeight += height
            }
            contentHeight += LayoutConstants.imageTextGap
        }
        if !blocks.isEmpty { contentHeight -= LayoutConstants.imageTextGap }  // 末块后无 gap

        return BlockMeasure(
            size: NodeSize(
                width: ceil(max(maxBlockWidth, 1)),
                // 顶部 padding 已随文本块偏移计入 contentHeight，此处只补底部 verticalPadding
                height: ceil(contentHeight + verticalPadding)
            ),
            blocks: blocks
        )
    }

    /// 文本换行后的行数（源行独立换行；空行计 1 行）。
    private func lineCount(
        _ text: String,
        maxWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> Int {
        var count = 0
        let sourceLines = text.components(separatedBy: "\n")
        for sourceLine in sourceLines {
            let characters = sourceLine.isEmpty ? [" "] : sourceLine.map(String.init)
            var currentLine = ""

            for character in characters {
                let candidate = currentLine + character
                if textWidth(candidate, attributes: attributes) > maxWidth,
                   !currentLine.isEmpty {
                    count += 1
                    currentLine = character
                } else {
                    currentLine = candidate
                }
            }

            count += 1
        }
        return count
    }

    /// 文本换行后各行最大宽度（源行独立换行；空行按空格宽计）。
    private func measureTextWidth(
        _ text: String,
        maxWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        var measuredWidth: CGFloat = 0
        let sourceLines = text.components(separatedBy: "\n")
        for sourceLine in sourceLines {
            let characters = sourceLine.isEmpty ? [" "] : sourceLine.map(String.init)
            var currentLine = ""

            for character in characters {
                let candidate = currentLine + character
                if textWidth(candidate, attributes: attributes) > maxWidth,
                   !currentLine.isEmpty {
                    measuredWidth = max(
                        measuredWidth,
                        textWidth(currentLine, attributes: attributes)
                    )
                    currentLine = character
                } else {
                    currentLine = candidate
                }
            }

            measuredWidth = max(
                measuredWidth,
                textWidth(currentLine.isEmpty ? " " : currentLine, attributes: attributes)
            )
        }
        return measuredWidth
    }

    private func textWidth(
        _ text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedText)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
