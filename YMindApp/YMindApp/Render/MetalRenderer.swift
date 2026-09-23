import AppKit
import MetalKit
import simd

struct CollapseBadge: Equatable {
    let nodeId: UUID
    let text: String
    let rect: CGRect

    static func make(for frame: NodeFrame) -> CollapseBadge? {
        guard frame.collapsed, frame.hiddenCount > 0 else { return nil }
        let text = String(frame.hiddenCount)
        let height: CGFloat = 20
        let width = max(height, 10 + CGFloat(text.count) * 7)
        return CollapseBadge(
            nodeId: frame.id,
            text: text,
            rect: CGRect(
                x: frame.rect.maxX - height + 7,
                y: frame.rect.maxY - height + 7,
                width: width,
                height: height
            )
        )
    }
}

final class MetalRenderer {
    enum RendererError: Error {
        case commandQueueUnavailable
        case shaderFunctionUnavailable(String)
    }

    private struct ViewportUniforms {
        let size: SIMD2<Float>
    }

    private struct SolidVertex {
        let position: SIMD2<Float>
        let color: SIMD4<Float>
    }

    private struct TexturedVertex {
        let position: SIMD2<Float>
        let textureCoordinate: SIMD2<Float>
        let color: SIMD4<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let texturedPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textAtlas = TextAtlas()
    private let badgeAtlas = CollapseBadgeAtlas()

    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        self.commandQueue = commandQueue

        let library = try device.makeDefaultLibrary(bundle: .main)
        guard let solidVertex = library.makeFunction(name: "solidVertex"),
              let solidFragment = library.makeFunction(name: "solidFragment"),
              let texturedVertex = library.makeFunction(name: "texturedVertex"),
              let texturedFragment = library.makeFunction(name: "texturedFragment") else {
            throw RendererError.shaderFunctionUnavailable("无法加载 Metal shader")
        }

        solidPipeline = try Self.makePipeline(
            device: device,
            vertex: solidVertex,
            fragment: solidFragment,
            premultipliedAlpha: false
        )
        texturedPipeline = try Self.makePipeline(
            device: device,
            vertex: texturedVertex,
            fragment: texturedFragment,
            premultipliedAlpha: true
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.shaderFunctionUnavailable("无法创建文字采样器")
        }
        self.sampler = sampler
    }

    func draw(
        in view: MTKView,
        snapshot: LayoutSnapshot,
        camera: Camera,
        selectedId: UUID?
    ) {
        guard view.bounds.width > 0,
              view.bounds.height > 0,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let background = rgba(NSColor.windowBackgroundColor)
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background.x),
            green: Double(background.y),
            blue: Double(background.z),
            alpha: Double(background.w)
        )
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.label = "YMind 画布"

        var viewport = ViewportUniforms(
            size: SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        )

        // 绘制顺序：边 → 节点底色 → 文字 → 折叠徽章 → 选中描边。
        drawSolid(
            edgeVertices(snapshot: snapshot, camera: camera),
            encoder: encoder,
            viewport: &viewport
        )
        drawSolid(
            fillVertices(snapshot: snapshot, camera: camera),
            encoder: encoder,
            viewport: &viewport
        )
        drawText(
            snapshot: snapshot,
            camera: camera,
            view: view,
            encoder: encoder,
            viewport: &viewport
        )
        drawBadges(
            snapshot: snapshot,
            camera: camera,
            view: view,
            encoder: encoder,
            viewport: &viewport
        )
        if let selectedId, let selectedFrame = snapshot.frames[selectedId] {
            drawSolid(
                strokeVertices(frame: selectedFrame, camera: camera),
                encoder: encoder,
                viewport: &viewport
            )
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func makePipeline(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        premultipliedAlpha: Bool
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = premultipliedAlpha ? .one : .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func drawSolid(
        _ vertices: [SolidVertex],
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<SolidVertex>.stride * vertices.count
              ) else {
            return
        }

        encoder.setRenderPipelineState(solidPipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &viewport,
            length: MemoryLayout<ViewportUniforms>.stride,
            index: 1
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawText(
        snapshot: LayoutSnapshot,
        camera: Camera,
        view: MTKView,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        let displayScale = view.window?.backingScaleFactor ?? 1
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)

        for frame in orderedFrames(snapshot) {
            guard let texture = textAtlas.texture(
                for: frame,
                text: frame.text,
                scale: displayScale,
                device: device
            ) else {
                continue
            }

            let color = rgba(frame.isRoot ? .white : .labelColor)
            let vertices = texturedQuad(frame: frame, camera: camera, color: color)
            guard let buffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<TexturedVertex>.stride * vertices.count
            ) else {
                continue
            }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &viewport,
                length: MemoryLayout<ViewportUniforms>.stride,
                index: 1
            )
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
    }

    private func edgeVertices(snapshot: LayoutSnapshot, camera: Camera) -> [SolidVertex] {
        let color = rgba(.separatorColor)
        let thickness = max(1.25, min(3, 2 * camera.scale))
        return snapshot.edges.flatMap { edge in
            zip(edge.points, edge.points.dropFirst()).flatMap { start, end in
                segmentQuad(
                    from: camera.worldToScreen(start),
                    to: camera.worldToScreen(end),
                    thickness: thickness,
                    color: color
                )
            }
        }
    }

    private func drawBadges(
        snapshot: LayoutSnapshot,
        camera: Camera,
        view: MTKView,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        let badges = orderedFrames(snapshot).compactMap(CollapseBadge.make(for:))
        let badgeColor = rgba(.controlAccentColor)
        drawSolid(
            badges.flatMap {
                pillVertices(rect: screenRect($0.rect, camera: camera), color: badgeColor)
            },
            encoder: encoder,
            viewport: &viewport
        )

        let displayScale = view.window?.backingScaleFactor ?? 1
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for badge in badges {
            guard let texture = badgeAtlas.texture(
                for: badge,
                scale: displayScale,
                device: device
            ) else {
                continue
            }
            let rect = screenRect(badge.rect, camera: camera)
            let vertices = texturedQuad(rect: rect, color: rgba(.white))
            guard let buffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<TexturedVertex>.stride * vertices.count
            ) else {
                continue
            }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &viewport,
                length: MemoryLayout<ViewportUniforms>.stride,
                index: 1
            )
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
    }

    private func fillVertices(snapshot: LayoutSnapshot, camera: Camera) -> [SolidVertex] {
        orderedFrames(snapshot).flatMap { frame in
            let color = rgba(
                frame.isRoot
                    ? NSColor.controlAccentColor
                    : NSColor.controlBackgroundColor
            )
            return rectangleQuad(rect: screenRect(frame.rect, camera: camera), color: color)
        }
    }

    private func strokeVertices(frame: NodeFrame, camera: Camera) -> [SolidVertex] {
        let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
        let color = rgba(.keyboardFocusIndicatorColor)
        let thickness: CGFloat = 2
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: thickness)
        let bottom = CGRect(
            x: rect.minX,
            y: rect.maxY - thickness,
            width: rect.width,
            height: thickness
        )
        let left = CGRect(x: rect.minX, y: rect.minY, width: thickness, height: rect.height)
        let right = CGRect(
            x: rect.maxX - thickness,
            y: rect.minY,
            width: thickness,
            height: rect.height
        )
        return [top, bottom, left, right].flatMap {
            rectangleQuad(rect: $0, color: color)
        }
    }

    private func texturedQuad(
        frame: NodeFrame,
        camera: Camera,
        color: SIMD4<Float>
    ) -> [TexturedVertex] {
        texturedQuad(rect: screenRect(frame.rect, camera: camera), color: color)
    }

    private func texturedQuad(
        rect: CGRect,
        color: SIMD4<Float>
    ) -> [TexturedVertex] {
        let topLeft = SIMD2(Float(rect.minX), Float(rect.minY))
        let topRight = SIMD2(Float(rect.maxX), Float(rect.minY))
        let bottomLeft = SIMD2(Float(rect.minX), Float(rect.maxY))
        let bottomRight = SIMD2(Float(rect.maxX), Float(rect.maxY))

        // Core Graphics 位图的首行是底边，因此这里翻转纹理 V 坐标。
        return [
            TexturedVertex(position: topLeft, textureCoordinate: SIMD2(0, 1), color: color),
            TexturedVertex(position: bottomLeft, textureCoordinate: SIMD2(0, 0), color: color),
            TexturedVertex(position: topRight, textureCoordinate: SIMD2(1, 1), color: color),
            TexturedVertex(position: topRight, textureCoordinate: SIMD2(1, 1), color: color),
            TexturedVertex(position: bottomLeft, textureCoordinate: SIMD2(0, 0), color: color),
            TexturedVertex(position: bottomRight, textureCoordinate: SIMD2(1, 0), color: color),
        ]
    }

    private func pillVertices(rect: CGRect, color: SIMD4<Float>) -> [SolidVertex] {
        let radius = min(rect.height / 2, rect.width / 2)
        var vertices = rectangleQuad(
            rect: CGRect(
                x: rect.minX + radius,
                y: rect.minY,
                width: max(rect.width - radius * 2, 0),
                height: rect.height
            ),
            color: color
        )
        vertices += rectangleQuad(
            rect: CGRect(
                x: rect.minX,
                y: rect.minY + radius,
                width: rect.width,
                height: max(rect.height - radius * 2, 0)
            ),
            color: color
        )
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: rect.minX + radius, y: rect.minY + radius), .pi),
            (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), -.pi / 2),
            (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 0),
            (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), .pi / 2),
        ]
        for (center, startAngle) in corners {
            for index in 0..<4 {
                let first = startAngle + CGFloat(index) * .pi / 8
                let second = startAngle + CGFloat(index + 1) * .pi / 8
                vertices += [
                    solidVertex(x: center.x, y: center.y, color: color),
                    solidVertex(
                        x: center.x + cos(first) * radius,
                        y: center.y + sin(first) * radius,
                        color: color
                    ),
                    solidVertex(
                        x: center.x + cos(second) * radius,
                        y: center.y + sin(second) * radius,
                        color: color
                    ),
                ]
            }
        }
        return vertices
    }

    private func rectangleQuad(rect: CGRect, color: SIMD4<Float>) -> [SolidVertex] {
        let topLeft = solidVertex(x: rect.minX, y: rect.minY, color: color)
        let topRight = solidVertex(x: rect.maxX, y: rect.minY, color: color)
        let bottomLeft = solidVertex(x: rect.minX, y: rect.maxY, color: color)
        let bottomRight = solidVertex(x: rect.maxX, y: rect.maxY, color: color)
        return [topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight]
    }

    private func segmentQuad(
        from start: CGPoint,
        to end: CGPoint,
        thickness: CGFloat,
        color: SIMD4<Float>
    ) -> [SolidVertex] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let offset = CGPoint(
            x: -dy / length * thickness / 2,
            y: dx / length * thickness / 2
        )
        let a = solidVertex(x: start.x + offset.x, y: start.y + offset.y, color: color)
        let b = solidVertex(x: start.x - offset.x, y: start.y - offset.y, color: color)
        let c = solidVertex(x: end.x + offset.x, y: end.y + offset.y, color: color)
        let d = solidVertex(x: end.x - offset.x, y: end.y - offset.y, color: color)
        return [a, b, c, c, b, d]
    }

    private func solidVertex(x: CGFloat, y: CGFloat, color: SIMD4<Float>) -> SolidVertex {
        SolidVertex(position: SIMD2(Float(x), Float(y)), color: color)
    }

    private func screenRect(_ rect: CGRect, camera: Camera) -> CGRect {
        let origin = camera.worldToScreen(rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * camera.scale,
            height: rect.height * camera.scale
        )
    }

    private func orderedFrames(_ snapshot: LayoutSnapshot) -> [NodeFrame] {
        snapshot.frames.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func rgba(_ color: NSColor) -> SIMD4<Float> {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD4(
            Float(converted.redComponent),
            Float(converted.greenComponent),
            Float(converted.blueComponent),
            Float(converted.alphaComponent)
        )
    }
}
