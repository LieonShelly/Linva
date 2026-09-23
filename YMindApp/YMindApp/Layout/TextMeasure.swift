import AppKit
import CoreText

struct TextMeasure {
    func size(for node: Node, isRoot: Bool) -> NodeSize {
        let font = NSFont.systemFont(
            ofSize: isRoot ? 18.4 : 14.7,
            weight: isRoot ? .bold : .medium
        )
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth = isRoot
            ? LayoutConstants.rootMaxTextWidth
            : LayoutConstants.nodeMaxTextWidth

        var measuredWidth: CGFloat = 0
        var lineCount = 0

        let sourceLines = node.text.components(separatedBy: "\n")
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
                    lineCount += 1
                    currentLine = character
                } else {
                    currentLine = candidate
                }
            }

            measuredWidth = max(
                measuredWidth,
                textWidth(currentLine.isEmpty ? " " : currentLine, attributes: attributes)
            )
            lineCount += 1
        }

        let horizontalPadding = isRoot
            ? LayoutConstants.rootPadX
            : LayoutConstants.nodePadX
        let verticalPadding = isRoot
            ? LayoutConstants.rootPadY
            : LayoutConstants.nodePadY
        let lineHeight = isRoot
            ? LayoutConstants.rootLineHeight
            : LayoutConstants.nodeLineHeight

        return NodeSize(
            width: ceil(measuredWidth + horizontalPadding * 2),
            height: ceil(CGFloat(lineCount) * lineHeight + verticalPadding * 2)
        )
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
