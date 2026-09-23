import CoreGraphics
import Foundation

struct Camera: Equatable {
    var translation: CGPoint = .zero
    var scale: CGFloat = 1

    mutating func fit(contentBounds: CGRect, viewport: CGSize) {
        guard !contentBounds.isNull, !contentBounds.isEmpty else { return }

        let pad: CGFloat = 80
        let contentW = max(contentBounds.width, 1)
        let contentH = max(contentBounds.height, 1)
        scale = min(
            1.15,
            max(
                0.35,
                min(
                    (viewport.width - pad * 2) / contentW,
                    (viewport.height - pad * 2) / contentH
                )
            )
        )

        let cx = contentBounds.midX
        let cy = contentBounds.midY
        translation = CGPoint(
            x: viewport.width / 2 - cx * scale,
            y: viewport.height / 2 - cy * scale
        )
    }

    func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + translation.x,
            y: point.y * scale + translation.y
        )
    }

    func screenToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - translation.x) / scale,
            y: (point.y - translation.y) / scale
        )
    }
}
