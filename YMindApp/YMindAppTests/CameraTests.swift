import CoreGraphics
import Testing
@testable import YMindApp

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
}
