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
    private let imageTextureCache: ImageTextureCache

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
        self.imageTextureCache = ImageTextureCache()
    }

    func draw(
        in view: MTKView,
        snapshot: LayoutSnapshot,
        camera: Camera,
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        selectedImageBlock: (nodeId: UUID, blockId: UUID)?,
        cutSourceIds: Set<UUID>,
        intent: DropIntent?,
        searchHitId: UUID?,
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

        encodeContent(
            into: encoder,
            viewportSize: view.bounds.size,
            snapshot: snapshot,
            camera: camera,
            displayScale: view.window?.backingScaleFactor ?? 1,
            selectedIds: selectedIds,
            selectionAnchorId: selectionAnchorId,
            selectedImageBlock: selectedImageBlock,
            cutSourceIds: cutSourceIds,
            intent: intent,
            searchHitId: searchHitId,
            marquee: marquee
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// 编码一帧的全部绘制内容；在线 draw(in:) 与离屏 renderImage 共用。
    private func encodeContent(
        into encoder: MTLRenderCommandEncoder,
        viewportSize: CGSize,
        snapshot: LayoutSnapshot,
        camera: Camera,
        displayScale: CGFloat,
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        selectedImageBlock: (nodeId: UUID, blockId: UUID)?,
        cutSourceIds: Set<UUID>,
        intent: DropIntent?,
        searchHitId: UUID?,
        marquee: CGRect?
    ) {
        var viewport = ViewportUniforms(
            size: SIMD2(Float(viewportSize.width), Float(viewportSize.height))
        )

        // R4 视口剔除：平移/缩放时逐帧工作 O(可见帧)，而非 O(全图)。
        let drawList = FrameDrawList.make(snapshot: snapshot, camera: camera, viewportSize: viewportSize)

        // 绘制顺序：边 → 节点底色 → 图片 → 文字 → 分叉控件 → 多选描边。
        drawSolid(
            edgeVertices(snapshot: snapshot, visibleIds: drawList.visibleIds, camera: camera),
            encoder: encoder,
            viewport: &viewport
        )
        drawSolid(
            fillVertices(frames: drawList.visible, camera: camera),
            encoder: encoder,
            viewport: &viewport
        )
        drawImage(
            snapshot: snapshot, drawList: drawList,
            camera: camera, displayScale: displayScale,
            selectedImageBlock: selectedImageBlock,
            encoder: encoder, viewport: &viewport
        )
        drawText(
            snapshot: snapshot, drawList: drawList,
            camera: camera, displayScale: displayScale,
            encoder: encoder,
            viewport: &viewport
        )
        drawBranchToggles(
            snapshot: snapshot, visibleIds: drawList.visibleIds,
            camera: camera, displayScale: displayScale,
            encoder: encoder,
            viewport: &viewport
        )
        drawSelectionStrokes(
            snapshot: snapshot,
            camera: camera,
            selectedIds: selectedIds,
            selectionAnchorId: selectionAnchorId,
            selectedImageBlock: selectedImageBlock,
            encoder: encoder,
            viewport: &viewport
        )
        drawCutWeaken(
            snapshot: snapshot,
            camera: camera,
            cutSourceIds: cutSourceIds,
            encoder: encoder,
            viewport: &viewport
        )
        drawDropFeedback(
            snapshot: snapshot, camera: camera, intent: intent,
            encoder: encoder, viewport: &viewport
        )
        drawSearchHit(
            snapshot: snapshot, camera: camera, searchHitId: searchHitId,
            encoder: encoder, viewport: &viewport
        )
        if let marquee {
            drawMarquee(marquee, encoder: encoder, viewport: &viewport)
        }
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
        drawList: FrameDrawList,
        camera: Camera,
        displayScale: CGFloat,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        // 与分叉控件一致：按相机缩放向上量化栅格倍率，放大时不糊（缩放靠 bucket 重栅格）。
        let rasterScale = displayScale * Self.rasterBucket(camera.scale)

        // 性能（R1）：可见文本 quad 合并进一个顶点数组 → 单块 buffer，按纹理分段 draw。
        // 旧实现每文本块一次 device.makeBuffer（1921 节点 = 每帧 1921 次分配/上传）。
        // z 序由 pass 分层决定，frames 遍历顺序不影响像素（R2：不再排序）。
        // R4：只处理可见帧；驱逐用全量文本块 id（屏幕外节点纹理保留，平移回视不重建）。
        var quads: [(offset: Int, count: Int, texture: MTLTexture)] = []
        var vertices: [TexturedVertex] = []
        for frame in drawList.visible {
            for block in frame.blocks where block.text != nil {
                guard let texture = textAtlas.texture(
                    for: frame,
                    block: block,
                    scale: rasterScale,
                    device: device
                ) else {
                    continue
                }
                let worldRect = CGRect(
                    x: frame.rect.minX + block.rect.minX,
                    y: frame.rect.minY + block.rect.minY,
                    width: block.rect.width,
                    height: block.rect.height
                )
                let color = rgba(frame.isRoot ? .white : .labelColor)
                let quad = texturedQuad(rect: screenRect(worldRect, camera: camera), color: color)
                quads.append((offset: vertices.count, count: quad.count, texture: texture))
                vertices += quad
            }
        }
        textAtlas.evictUnused(known: drawList.allTextBlockIds)   // 节点删除/折叠/文本编辑后清理（显存纪律三）

        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(
                  bytes: vertices,
                  length: MemoryLayout<TexturedVertex>.stride * vertices.count
              ) else {
            return
        }
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &viewport,
            length: MemoryLayout<ViewportUniforms>.stride,
            index: 1
        )
        for quad in quads {
            encoder.setFragmentTexture(quad.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: quad.offset, vertexCount: quad.count)
        }
    }

    /// 图片 quad：视口剔除（帧级）→ 缓存纹理 → texturedQuad（与文字同管线）。
    private func drawImage(
        snapshot: LayoutSnapshot,
        drawList: FrameDrawList,
        camera: Camera,
        displayScale: CGFloat,
        selectedImageBlock: (nodeId: UUID, blockId: UUID)?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard !snapshot.imagePayloads.isEmpty else {
            // 全文档无图：提前返回前也清缓存（节点删图/折叠后 payloads 清空的兜底，显存纪律三）。
            imageTextureCache.evictUnused(known: [])
            return
        }

        let rasterScale = displayScale * Self.rasterBucket(camera.scale)

        // 性能（R1+R4）：可见图片 quad 合并进单块 buffer，按纹理分段 draw（同 drawText）；
        // 帧级剔除已保证只处理可见帧，块级视口检查由 FrameDrawList 的 -100pt 外扩覆盖。
        var quads: [(offset: Int, count: Int, texture: MTLTexture)] = []
        var vertices: [TexturedVertex] = []
        for frame in drawList.visible {
            for block in frame.blocks where block.text == nil {
                guard let payload = snapshot.imagePayloads[block.blockId] else { continue }
                let worldRect = CGRect(
                    x: frame.rect.minX + block.rect.minX,
                    y: frame.rect.minY + block.rect.minY,
                    width: block.rect.width,
                    height: block.rect.height
                )
                guard let texture = imageTextureCache.texture(
                    id: block.blockId,
                    localRect: block.rect,
                    payload: payload,
                    displayScale: rasterScale,
                    device: device
                ) else { continue }

                let quad = texturedQuad(
                    rect: screenRect(worldRect, camera: camera),
                    color: SIMD4<Float>(1, 1, 1, 1)
                )
                quads.append((offset: vertices.count, count: quad.count, texture: texture))
                vertices += quad
            }
        }
        imageTextureCache.evictUnused(known: drawList.allImageBlockIds)   // 节点删除/折叠后清理（显存纪律三）

        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(
                  bytes: vertices,
                  length: MemoryLayout<TexturedVertex>.stride * vertices.count
              ) else {
            return
        }
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &viewport,
            length: MemoryLayout<ViewportUniforms>.stride,
            index: 1
        )
        for quad in quads {
            encoder.setFragmentTexture(quad.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: quad.offset, vertexCount: quad.count)
        }
    }

    private func drawBranchToggles(
        snapshot: LayoutSnapshot,
        visibleIds: Set<UUID>,
        camera: Camera,
        displayScale: CGFloat,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        // R4：只画可见节点的分叉控件；展开态不渲染（仅折叠态显示），
        // 但 snapshot.branchToggles 保留全部，命中测试（CanvasHitTesting）仍可点折叠。
        let toggles = snapshot.branchToggles.filter {
            visibleIds.contains($0.nodeId) && $0.collapsed
        }
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
                // 展开态：外圈描边色 + 内圈填充色，二者同为胶囊/圆，描边才跟着轮廓走。
                solidVertices += pillVertices(rect: rect, color: border)
                solidVertices += pillVertices(
                    rect: rect.insetBy(dx: borderThickness, dy: borderThickness),
                    color: fill
                )
            }
        }
        drawSolid(solidVertices, encoder: encoder, viewport: &viewport)

        let rasterScale = displayScale * Self.rasterBucket(camera.scale)

        // 性能（R1）：分叉图标 quad 合并进单块 buffer，按纹理分段 draw（同 drawText）。
        var quads: [(offset: Int, count: Int, texture: MTLTexture)] = []
        var vertices: [TexturedVertex] = []
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
            let quad = texturedQuad(rect: rect, color: color)
            quads.append((offset: vertices.count, count: quad.count, texture: texture))
            vertices += quad
        }

        guard !vertices.isEmpty,
              let buffer = device.makeBuffer(
                  bytes: vertices,
                  length: MemoryLayout<TexturedVertex>.stride * vertices.count
              ) else {
            return
        }
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &viewport,
            length: MemoryLayout<ViewportUniforms>.stride,
            index: 1
        )
        for quad in quads {
            encoder.setFragmentTexture(quad.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: quad.offset, vertexCount: quad.count)
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

    /// 栅格倍率：按相机缩放向上量化到 0.5 档，并封顶 2×。
    /// 向上量化保证每档 ≥ 实际缩放（不会被放大糊掉）；封顶限制高缩放下的纹理内存。
    private static func rasterBucket(_ cameraScale: CGFloat) -> CGFloat {
        let clamped = min(max(cameraScale, 1), 2)
        return (clamped * 2).rounded(.up) / 2
    }

    /// 相机视口世界 AABB：视口四角 screenToWorld 反投影（相机仅平移+等比缩放，无旋转）。
    private static func viewportWorldRect(camera: Camera, viewportSize: CGSize) -> CGRect {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: viewportSize.width, y: 0),
            CGPoint(x: 0, y: viewportSize.height),
            CGPoint(x: viewportSize.width, y: viewportSize.height),
        ]
        let world = corners.map { camera.screenToWorld($0) }
        let xs = world.map(\.x)
        let ys = world.map(\.y)
        return CGRect(
            x: xs.min()!,
            y: ys.min()!,
            width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!
        )
    }

    /// 一帧的绘制列表（R4 视口剔除）：只处理可见帧，平移/缩放时开销 O(可见) 而非 O(全图)。
    /// 剔除边界外扩 100pt，避免贴边节点的文字/图片被切。
    private struct FrameDrawList {
        let visible: [NodeFrame]
        let visibleIds: Set<UUID>
        /// 全部文本块 id（驱逐缓存用；与可见性无关，节点仍在文档即保留纹理）。
        let allTextBlockIds: Set<UUID>
        /// 全部图片块 id（驱逐缓存用）。
        let allImageBlockIds: Set<UUID>

        static func make(snapshot: LayoutSnapshot, camera: Camera, viewportSize: CGSize) -> FrameDrawList {
            let viewport = viewportWorldRect(camera: camera, viewportSize: viewportSize)
                .insetBy(dx: -100, dy: -100)
            var visible: [NodeFrame] = []
            var textIds = Set<UUID>()
            var imageIds = Set<UUID>()
            // 一次遍历同时收集可见帧 + 全部块 id，避免多遍 O(全图)。
            for frame in snapshot.frames.values {
                for block in frame.blocks {
                    if block.text != nil {
                        textIds.insert(block.blockId)
                    } else {
                        imageIds.insert(block.blockId)
                    }
                }
                if frame.rect.intersects(viewport) {
                    visible.append(frame)
                }
            }
            return FrameDrawList(
                visible: visible,
                visibleIds: Set(visible.map(\.id)),
                allTextBlockIds: textIds,
                allImageBlockIds: imageIds
            )
        }
    }

    private func drawSelectionStrokes(
        snapshot: LayoutSnapshot,
        camera: Camera,
        selectedIds: Set<UUID>,
        selectionAnchorId: UUID?,
        selectedImageBlock: (nodeId: UUID, blockId: UUID)?,
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
                // 贴在成员描边外侧，虚线才不会被实线盖住；偏移随描边宽度缩放。
                vertices += dashedStrokeVertices(
                    rect: rect.insetBy(dx: -thickness, dy: -thickness),
                    thickness: thickness,
                    dash: 5 * camera.scale,
                    gap: 3 * camera.scale,
                    color: anchorColor
                )
            }
        }
        // 图片块级选中：按块世界 rect → 直角 4 边近似（v1 不新增圆角 shader）。
        if let sel = selectedImageBlock,
           let frame = snapshot.frames[sel.nodeId],
           let block = frame.blocks.first(where: { $0.blockId == sel.blockId }) {
            let worldRect = CGRect(
                x: frame.rect.minX + block.rect.minX,
                y: frame.rect.minY + block.rect.minY,
                width: block.rect.width,
                height: block.rect.height
            )
            vertices += strokeVertices(
                rect: screenRect(worldRect, camera: camera),
                thickness: max(1.5, 2 * camera.scale),
                color: rgba(.controlAccentColor)
            )
        }
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 剪切源弱化：半透明遮罩 + 虚线边框（对齐原型弱化/虚线）。
    private func drawCutWeaken(
        snapshot: LayoutSnapshot,
        camera: Camera,
        cutSourceIds: Set<UUID>,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard !cutSourceIds.isEmpty else { return }
        let fillColor = rgba(NSColor.windowBackgroundColor.withAlphaComponent(0.55))
        let dashColor = rgba(.tertiaryLabelColor)
        let thickness = max(1.5, 2 * camera.scale)
        var vertices: [SolidVertex] = []
        for id in cutSourceIds {
            guard let frame = snapshot.frames[id] else { continue }
            let rect = screenRect(frame.rect, camera: camera)
            vertices += rectangleQuad(rect: rect, color: fillColor)
            vertices += dashedStrokeVertices(
                rect: rect.insetBy(dx: -3, dy: -3),
                thickness: thickness,
                dash: 5 * camera.scale,
                gap: 3 * camera.scale,
                color: dashColor
            )
        }
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 放置反馈：child 整节点描边；before/after 弱边框+插入线；side 根镶边/中线引导。
    private func drawDropFeedback(
        snapshot: LayoutSnapshot,
        camera: Camera,
        intent: DropIntent?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard let intent else { return }
        let accent = rgba(.controlAccentColor)
        var vertices: [SolidVertex] = []
        switch intent {
        case let .child(targetId):
            guard let frame = snapshot.frames[targetId] else { return }
            let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
            vertices += strokeVertices(rect: rect, thickness: max(2.5, 3 * camera.scale), color: accent)

        case let .before(targetId), let .after(targetId):
            guard let frame = snapshot.frames[targetId] else { return }
            let weakColor = rgba(NSColor.controlAccentColor.withAlphaComponent(0.45))
            let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
            vertices += strokeVertices(rect: rect, thickness: max(1.5, 2 * camera.scale), color: weakColor)
            let y = intent == .before(targetId: targetId)
                ? screenRect(frame.rect, camera: camera).minY
                : screenRect(frame.rect, camera: camera).maxY
            vertices += horizontalLineQuad(
                center: CGPoint(x: screenRect(frame.rect, camera: camera).midX, y: y),
                width: max(screenRect(frame.rect, camera: camera).width, 48),
                thickness: 3,
                color: accent
            )

        case let .sideLeft(targetId, viaEmpty), let .sideRight(targetId, viaEmpty):
            guard let frame = snapshot.frames[targetId] else { return }
            if viaEmpty {
                // 中线引导：垂直贯穿线
                let cx = screenRect(frame.rect, camera: camera).midX
                vertices += verticalLineQuad(
                    x: cx,
                    top: 0,
                    bottom: camera.scale > 0 ? 4000 * camera.scale : 0,
                    thickness: 2,
                    color: rgba(NSColor.controlAccentColor.withAlphaComponent(0.55))
                )
            } else if case .sideLeft = intent {
                let rect = screenRect(frame.rect, camera: camera)
                vertices += edgeInsetQuad(rect: rect, edge: .left, thickness: 6, color: accent)
            } else {
                let rect = screenRect(frame.rect, camera: camera)
                vertices += edgeInsetQuad(rect: rect, edge: .right, thickness: 6, color: accent)
            }
        }
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 搜索命中：琥珀色描边（对齐原型 .is-search-hit），可与普通选中并存。
    private func drawSearchHit(
        snapshot: LayoutSnapshot,
        camera: Camera,
        searchHitId: UUID?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard let searchHitId, let frame = snapshot.frames[searchHitId] else { return }
        let amber = SIMD4<Float>(0.7686, 0.4706, 0.1647, 1)  // #C4782A
        let rect = screenRect(frame.rect, camera: camera).insetBy(dx: -3, dy: -3)
        let vertices = strokeVertices(rect: rect, thickness: max(2, 2.5 * camera.scale), color: amber)
        drawSolid(vertices, encoder: encoder, viewport: &viewport)
    }

    /// 水平插入线：中心点 + 宽度。
    private func horizontalLineQuad(center: CGPoint, width: CGFloat, thickness: CGFloat, color: SIMD4<Float>) -> [SolidVertex] {
        rectangleQuad(
            rect: CGRect(x: center.x - width / 2, y: center.y - thickness / 2, width: width, height: thickness),
            color: color
        )
    }

    /// 垂直贯穿线。
    private func verticalLineQuad(x: CGFloat, top: CGFloat, bottom: CGFloat, thickness: CGFloat, color: SIMD4<Float>) -> [SolidVertex] {
        rectangleQuad(
            rect: CGRect(x: x - thickness / 2, y: top, width: thickness, height: max(bottom - top, 1)),
            color: color
        )
    }

    /// 根节点左右镶边。
    private func edgeInsetQuad(rect: CGRect, edge: EdgeInset, thickness: CGFloat, color: SIMD4<Float>) -> [SolidVertex] {
        switch edge {
        case .left:
            return rectangleQuad(rect: CGRect(x: rect.minX, y: rect.minY, width: thickness, height: rect.height), color: color)
        case .right:
            return rectangleQuad(rect: CGRect(x: rect.maxX - thickness, y: rect.minY, width: thickness, height: rect.height), color: color)
        }
    }

    private enum EdgeInset { case left, right }

    private func edgeVertices(
        snapshot: LayoutSnapshot,
        visibleIds: Set<UUID>,
        camera: Camera
    ) -> [SolidVertex] {
        let color = rgba(.separatorColor)
        let thickness = max(1.25, min(3, 2 * camera.scale))
        // R4：任一端点可见才画该边。
        return snapshot.edges
            .filter { visibleIds.contains($0.fromId) || visibleIds.contains($0.toId) }
            .flatMap { edge in
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

    private func fillVertices(frames: [NodeFrame], camera: Camera) -> [SolidVertex] {
        // R4：只处理可见帧。
        frames.flatMap { frame in
            let rect = screenRect(frame.rect, camera: camera)
            if let fill = frame.fill {
                if frame.isRoot {
                    return rectangleQuad(
                        rect: rect,
                        color: rgba(NodeFillStyle.rootBackground(fill))
                    )
                } else {
                    var vertices = rectangleQuad(
                        rect: rect,
                        color: rgba(NodeFillStyle.background(fill))
                    )
                    vertices += strokeVertices(
                        rect: rect,
                        thickness: max(1, 1.5 * camera.scale),
                        color: rgba(NodeFillStyle.border(fill))
                    )
                    return vertices
                }
            } else {
                let color = rgba(
                    frame.isRoot
                        ? NSColor.controlAccentColor
                        : NSColor.controlBackgroundColor
                )
                return rectangleQuad(rect: rect, color: color)
            }
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

    private func rgba(_ color: NSColor) -> SIMD4<Float> {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD4(
            Float(converted.redComponent),
            Float(converted.greenComponent),
            Float(converted.blueComponent),
            Float(converted.alphaComponent)
        )
    }

    /// 导出：把 `contentBounds` 以 `scale = min(2, maxDimension / 长边)` 光栅化到离屏纹理，
    /// 仅画边/节点块/文字/填色（不画分叉 ± 与交互 UI），返回 CGImage。
    func renderImage(
        snapshot: LayoutSnapshot,
        contentBounds: CGRect,
        maxDimension: CGFloat = 2400,
        padding: CGFloat = 48,
        paper: NSColor,
        selectedImageBlock: (nodeId: UUID, blockId: UUID)? = nil
    ) -> CGImage? {
        guard !contentBounds.isNull, !contentBounds.isEmpty else { return nil }

        let contentW = max(contentBounds.width, 1)
        let contentH = max(contentBounds.height, 1)
        let scale = min(max(maxDimension / max(contentW, contentH), 0.35), 2)
        let pixelW = max(Int(ceil((contentW + padding * 2) * scale)), 1)
        let pixelH = max(Int(ceil((contentH + padding * 2) * scale)), 1)

        var camera = Camera()
        camera.scale = scale
        camera.translation = CGPoint(
            x: padding * scale - contentBounds.minX * scale,
            y: padding * scale - contentBounds.minY * scale
        )

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelW,
            height: pixelH,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        let background = rgba(paper)
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background.x),
            green: Double(background.y),
            blue: Double(background.z),
            alpha: Double(background.w)
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        encoder.label = "YMind 导出"

        // 导出不含分叉 ± 控件：LayoutSnapshot 缺省 branchToggles 为空。
        // imagePayloads 必须随行：否则 drawImage 见不到图，导出缺图。
        let exportSnapshot = LayoutSnapshot(
            frames: snapshot.frames,
            edges: snapshot.edges,
            imagePayloads: snapshot.imagePayloads
        )

        // 导出固定按浅色纸面解析动态语义色，结果与系统外观无关。
        let appearance = NSAppearance(named: .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            encodeContent(
                into: encoder,
                viewportSize: CGSize(width: pixelW, height: pixelH),
                snapshot: exportSnapshot,
                camera: camera,
                displayScale: 1,
                selectedIds: [],
                selectionAnchorId: nil,
                selectedImageBlock: selectedImageBlock,
                cutSourceIds: [],
                intent: nil,
                searchHitId: nil,
                marquee: nil
            )
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let region = MTLRegionMake2D(0, 0, pixelW, pixelH)
        var bytes = [UInt8](repeating: 0, count: pixelW * pixelH * 4)
        texture.getBytes(&bytes, bytesPerRow: pixelW * 4, from: region, mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: pixelW,
                height: pixelH,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: pixelW * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return image
    }
}
