import CoreGraphics
import Testing
@testable import LinvaApp

@Suite("Camera")
struct CameraTests {
    @Test func worldToScreen_roundTrip() {
        let camera = Camera(
            translation: CGPoint(x: 10, y: 20),
            scale: 2
        )
        let world = CGPoint(x: 5, y: 5)

        let screen = camera.worldToScreen(world)
        let result = camera.screenToWorld(screen)

        #expect(result.x == world.x)
        #expect(result.y == world.y)
    }

    @Test func center_keepsScale_andCentersRect() {
        var camera = Camera(translation: CGPoint(x: 100, y: 80), scale: 2)
        let rect = CGRect(x: 50, y: 60, width: 20, height: 10)
        camera.center(on: rect, viewport: CGSize(width: 400, height: 300))

        #expect(camera.scale == 2)                       // 保持缩放
        let c = camera.worldToScreen(CGPoint(x: rect.midX, y: rect.midY))
        #expect(abs(c.x - 200) < 0.001)                  // 视口水平中心
        #expect(abs(c.y - 150) < 0.001)                  // 视口垂直中心
    }
}
