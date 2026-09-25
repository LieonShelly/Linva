import AppKit
import MetalKit
import simd

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
    private let branchToggleAtlas = BranchToggleAtlas()

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
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        marquee: CGRect?
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

        // 绘制顺序：边 → 节点底色 → 文字 → 分叉控件 → 多选描边。
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
        drawBranchToggles(
            snapshot: snapshot,
            camera: camera,
            view: view,
            encoder: encoder,
            viewport: &viewport
        )
        drawSelectionStrokes(
            snapshot: snapshot,
            camera: camera,
            selectedIds: selectedIds,
            selectionAnchorId: selectionAnchorId,
            encoder: encoder,
            viewport: &viewport
        )
        if let marquee {
            drawMarquee(marquee, encoder: encoder, viewport: &viewport)
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

    private func drawBranchToggles(
        snapshot: LayoutSnapshot,
        camera: Camera,
        view: MTKView,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        let toggles = snapshot.branchToggles
        guard !toggles.isEmpty else { return }

        let fill = rgba(.controlBackgroundColor)
        let accent = rgba(.controlAccentColor)
        let border = rgba(NSColor.controlAccentColor.withAlphaComponent(0.55))
        let borderThickness = max(1, 1.5 * camera.scale)

        var solidVertices: [SolidVertex] = []
        var rects: [(toggle: BranchToggle, rect: CGRect)] = []
        for toggle in toggles {
            let rect = toggleScreenRect(toggle, camera: camera)
            rects.append((toggle, rect))
            if toggle.collapsed {
                // 折叠态：强调色实心（对齐原型 .is-collapsed）。
                solidVertices += pillVertices(rect: rect, color: accent)
            } else {
                solidVertices += pillVertices(rect: rect, color: fill)
                solidVertices += strokeVertices(
                    rect: rect,
                    thickness: borderThickness,
                    color: border
                )
            }
        }
        drawSolid(solidVertices, encoder: encoder, viewport: &viewport)

        let displayScale = view.window?.backingScaleFactor ?? 1
        let rasterScale = displayScale * Self.rasterBucket(camera.scale)
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for (toggle, rect) in rects {
            let size = CGSize(
                width: rect.width / max(camera.scale, 0.001),
                height: rect.height / max(camera.scale, 0.001)
            )
            guard let texture = branchToggleAtlas.texture(
                for: toggle,
                size: size,
                scale: rasterScale,
                device: device
            ) else {
                continue
            }
            let color = rgba(toggle.collapsed ? .white : .controlAccentColor)
            let vertices = texturedQuad(rect: rect, color: color)
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

    /// 框选矩形（视图坐标），画在最上层。
    private func drawMarquee(
        _ rect: CGRect,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        var vertices = rectangleQuad(
            rect: rect,
            color: rgba(NSColor.controlAccentColor.withAlphaComponent(0.12))
        )
        vertices += strokeVertices(
            rect: rect,
            thickness: 1.5,
            color: rgba(NSColor.controlAccentColor.withAlphaComponent(0.8))
        )
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 控件外框（屏幕坐标）；几何来源与命中测试共享。
    private func toggleScreenRect(_ toggle: BranchToggle, camera: Camera) -> CGRect {
        let world = branchToggleWorldRect(toggle)
        let origin = camera.worldToScreen(world.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: world.width * camera.scale,
            height: world.height * camera.scale
        )
    }

    /// 栅格倍率量化到档位：缩放抖动时不重复栅格化，同时保证高缩放下文字不糊。
    private static func rasterBucket(_ cameraScale: CGFloat) -> CGFloat {
        switch cameraScale {
        case ..<1.25: return 1
        case ..<1.75: return 1.5
        case ..<2.5: return 2
        default: return 3
        }
    }

    private func drawSelectionStrokes(
        snapshot: LayoutSnapshot,
        camera: Camera,
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        let memberColor = rgba(.keyboardFocusIndicatorColor)
        let anchorColor = rgba(.controlAccentColor)
        let distinguishAnchor = selectedIds.count > 1
        let thickness = max(1.5, 2 * camera.scale)
        var vertices: [SolidVertex] = []
        for id in selectedIds {
            guard let frame = snapshot.frames[id] else { continue }
            let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
            vertices += strokeVertices(rect: rect, thickness: thickness, color: memberColor)
            if distinguishAnchor, id == selectionAnchorId {
                vertices += dashedStrokeVertices(
                    rect: rect.insetBy(dx: -4, dy: -4),
                    thickness: thickness,
                    dash: 5 * camera.scale,
                    gap: 3 * camera.scale,
                    color: anchorColor
                )
            }
        }
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
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

    private func strokeVertices(
        rect: CGRect,
        thickness: CGFloat,
        color: SIMD4<Float>
    ) -> [SolidVertex] {
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

    /// 沿矩形四边顺时针铺 dash，转角处不强行对齐（视觉上无碍，锚点仅作区分）。
    private func dashedStrokeVertices(
        rect: CGRect,
        thickness: CGFloat,
        dash: CGFloat,
        gap: CGFloat,
        color: SIMD4<Float>
    ) -> [SolidVertex] {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
        ]
        let step = max(dash + gap, 0.5)
        var vertices: [SolidVertex] = []
        for (start, end) in zip(corners, corners.dropFirst()) {
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { continue }
            let ux = (end.x - start.x) / length
            let uy = (end.y - start.y) / length
            var offset: CGFloat = 0
            while offset < length {
                let segment = min(dash, length - offset)
                vertices += segmentQuad(
                    from: CGPoint(x: start.x + ux * offset, y: start.y + uy * offset),
                    to: CGPoint(
                        x: start.x + ux * (offset + segment),
                        y: start.y + uy * (offset + segment)
                    ),
                    thickness: thickness,
                    color: color
                )
                offset += step
            }
        }
        return vertices
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

        // 上传前已把位图翻成「首行=顶边」，与 Metal 采样 (0,0)=纹理顶边一致。
        return [
            TexturedVertex(position: topLeft, textureCoordinate: SIMD2(0, 0), color: color),
            TexturedVertex(position: bottomLeft, textureCoordinate: SIMD2(0, 1), color: color),
            TexturedVertex(position: topRight, textureCoordinate: SIMD2(1, 0), color: color),
            TexturedVertex(position: topRight, textureCoordinate: SIMD2(1, 0), color: color),
            TexturedVertex(position: bottomLeft, textureCoordinate: SIMD2(0, 1), color: color),
            TexturedVertex(position: bottomRight, textureCoordinate: SIMD2(1, 1), color: color),
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
