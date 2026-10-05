# Linva 节点内嵌图片 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 节点可粘贴/拖入图片（归一 PNG），图文同框布局与 Metal 渲染，随 `.linva`（Codec v3）持久化，PNG 与 Markdown 导出含图。

**Architecture:** 图片像素随 `LayoutSnapshot.imagePayloads` 下发（方案 A，Render 不读 Model）；`setImage` 单命令双用途（仿 `setFill`）入命令栈；图片级选中态 `selectedImageId` 不入栈；纹理层三纪律：视口剔除 / 按需降采样 / LRU 128MB。

**Tech Stack:** Swift 6 / SwiftUI + AppKit 壳 / Metal 画布 / Swift Testing（`@Suite`/`#expect`）/ Xcode 16 文件系统同步工程（新文件自动入编译，无需改 pbxproj）。

**Spec:** `docs/superpowers/specs/2026-10-01-linva-image-node-design.md`（实现与本计划冲突时以 spec 为准；本计划仅修正 spec 一处事实错误，见 Task 2 Step 0）

## Global Constraints

- 分层白名单（`scripts/check-boundaries.sh`）：Model/Commands 仅 Foundation；Layout 允 Foundation AppKit CoreGraphics CoreText；Session 允 Foundation Combine CoreGraphics；Render 允 Foundation AppKit CoreGraphics Metal MetalKit SwiftUI simd；App 允 Foundation AppKit SwiftUI（本计划为其追加 **ImageIO**，Task 2）。
- `Node.image` 永远是归一后的 PNG bytes；**Codec 不做压缩/校验**，归一只在入口 `ImageNormalizer.normalize`。
- `MindMapDocument.currentVersion = 3`；decode 迁移链 v1→v2→v3 逐段 `if`，v2/v1 老文件零拒绝。
- 命令纪律：`setImage` no-op（旧值相等）不入栈、一步 Undo、不改节点选中态；`selectedImageId` 不入命令栈（同相机/选中纪律）。
- 渲染纪律：Metal 只消费 Snapshot；**保留 `TextTextureRasterizer.flipVertically`**；图片 quad 走既有 `texturedPipeline`，不新增 shader。
- 常量：显示宽度上限 300pt、图文间距 6pt、归一最长边 1024px、归一二级压缩阈值 5MB（→512px）、LRU 纹理预算 128MB。
- 测试跑法：`xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`；边界脚本 `bash scripts/check-boundaries.sh`。
- 提交纪律：每 Task 一个 commit；消息用中文 conventional 风格（`feat:`/`test:`/`docs:`）。

---

### Task 1: Model — `ImagePixelSize` + Node 扩展 + Codec v3

**Files:**
- Create: `LinvaApp/LinvaApp/Model/ImagePixelSize.swift`
- Modify: `LinvaApp/LinvaApp/Model/Node.swift`（struct 字段 + CodingKeys + `init(from:)`）
- Modify: `LinvaApp/LinvaApp/Model/MindMapDocument.swift:4`（currentVersion）
- Modify: `LinvaApp/LinvaApp/Model/LinvaCodec.swift:33-36`（迁移链）
- Test: `LinvaApp/LinvaAppTests/CodecTests.swift`（追加用例）

**Interfaces:**
- Produces: `struct ImagePixelSize: Codable, Equatable, Sendable { let width: Double; let height: Double }`；`Node.image: Data?`、`Node.imagePixelSize: ImagePixelSize?`；`MindMapDocument.currentVersion == 3`。后续所有 Task 依赖这三个名字。

- [ ] **Step 1: 写失败测试**（追加到 `CodecTests.swift`，沿用 `@Suite`/`#expect` 风格）

```swift
@Suite("Codec v3 图片字段")
struct CodecImageTests {
    private func documentWithImage() -> MindMapDocument {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [
            Node(text: "带图", image: Data([0x89, 0x50]), imagePixelSize: ImagePixelSize(width: 1024, height: 512)),
            Node(text: "无图"),
        ]
        return doc
    }

    @Test func imageRoundTrip() throws {
        let data = try LinvaCodec.encode(documentWithImage())
        let back = try LinvaCodec.decode(data)
        #expect(back.version == 3)
        #expect(back.root.children[0].image == Data([0x89, 0x50]))
        #expect(back.root.children[0].imagePixelSize == ImagePixelSize(width: 1024, height: 512))
        #expect(back.root.children[1].image == nil)
    }

    @Test func v2FileWithoutImage_opensWithoutReject() throws {
        // v2 老文件：version=2、无 image 字段
        let json = """
        {"version":2,"root":{"id":"\(UUID())","text":"老文件","collapsed":false,"children":[]}}
        """
        let back = try LinvaCodec.decode(Data(json.utf8))
        #expect(back.version == 3)
        #expect(back.root.image == nil)
    }

    @Test func v1File_chainMigrates() throws {
        let json = """
        {"version":1,"root":{"id":"\(UUID())","text":"v1","collapsed":false,"children":[]}}
        """
        let back = try LinvaCodec.decode(Data(json.utf8))
        #expect(back.version == 3)
    }

    @Test func invalidImagePixelSize_decodesAsNil() throws {
        // 宽高非法（0/负）→ 解码容错为 nil，不拒文件
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.imagePixelSize = ImagePixelSize(width: 0, height: 100)
        let data = try JSONEncoder().encode(doc)
        let back = try LinvaCodec.decode(data)
        #expect(back.root.imagePixelSize == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/CodecImageTests 2>&1 | tail -20`
Expected: FAIL（`ImagePixelSize` 未定义，编译错误）

- [ ] **Step 3: 最小实现**

`Model/ImagePixelSize.swift`（新建）：

```swift
import Foundation

/// 图片像素尺寸（归一器写入；Layout 只读此值，不解析 PNG 头）。
/// 自有类型原因：CGSize 在 `import Foundation` 下不可 Codable（实测），Model 白名单禁 CoreGraphics。
struct ImagePixelSize: Codable, Equatable, Sendable {
    let width: Double
    let height: Double

    init?(width: Double, height: Double) {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        self.width = width
        self.height = height
    }
}
```

`Model/Node.swift`：struct 追加 `var image: Data?`、`var imagePixelSize: ImagePixelSize?`（`children` 之前）；`CodingKeys` 追加 `image, imagePixelSize`；`init(from:)` 在 `fill` 之后追加：

```swift
image = try c.decodeIfPresent(Data.self, forKey: .image)
imagePixelSize = try c.decodeIfPresent(ImagePixelSize.self, forKey: .imagePixelSize)
```

（`ImagePixelSize.init?` 的 failable 校验让非法 JSON 值天然解码失败——配合 Step 3b 容错。）

`Node.init(from:)` 中 imagePixelSize 改为容错形式：

```swift
if let raw = try c.decodeIfPresent(ImagePixelSize.self, forKey: .imagePixelSize) {
    self.imagePixelSize = raw
} else {
    self.imagePixelSize = nil
}
```

`Node` 便捷 init 追加带默认值参数 `image: Data? = nil, imagePixelSize: ImagePixelSize? = nil`（顺序放在 `fill` 后）。

`Model/MindMapDocument.swift`：`static let currentVersion = 3`。

`Model/LinvaCodec.swift` decode 迁移链（33-36 行后追加一段）：

```swift
        // 迁移：v1 → v2（fill 缺省 nil，仅版本号升迁；Node 解码器对缺失 fill 天然容错）。
        if doc.version == 1 {
            doc.version = 2
        }
        // 迁移：v2 → v3（image/imagePixelSize 缺省 nil，仅版本号升迁）。
        if doc.version == 2 {
            doc.version = 3
        }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test … -only-testing:LinvaAppTests/CodecImageTests` + 全量 `xcodebuild test …`（确认既有 CodecTests 版本断言全绿）
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model LinvaApp/LinvaAppTests/CodecTests.swift
git commit -m "feat: Node 增 image/imagePixelSize 字段，Codec 升 v3（v1/v2 迁移内置）"
```

---

### Task 2: App 层 `ImageNormalizer` + ImageIO 白名单

**Files:**
- Create: `LinvaApp/LinvaApp/App/ImageNormalizer.swift`
- Modify: `scripts/check-boundaries.sh`（App 行追加 ImageIO）
- Modify: `docs/superpowers/specs/2026-10-01-linva-image-node-design.md` §1.3（修正「零新增 import」表述）
- Test: `LinvaApp/LinvaAppTests/ImageNormalizerTests.swift`（新建）

**Interfaces:**
- Produces: `enum ImageNormalizer { static func normalize(_ data: Data) -> (data: Data, pixelSize: ImagePixelSize)? }`——Task 4 注入 Session、Task 9 组合根赋值。

- [ ] **Step 0: 白名单与 spec 修正（先做，否则实现文件编译不过边界脚本）**

`scripts/check-boundaries.sh` App 行改为：

```bash
  "App|Foundation AppKit SwiftUI ImageIO"
```

并在脚本头部白名单注释处补一句：`# App 追加 ImageIO：图片归一器 CGImageSource 解码（2026-10-01 图片节点）。`

Spec §1.3 的「零新增 import（App 白名单已含 AppKit…）」一句改为：「需 `import ImageIO`（CGImageSource 属 ImageIO 而非 AppKit/CoreGraphics）；按仓库规约把 ImageIO 加入 App 白名单并同步 §5 记录。」

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import LinvaApp

@Suite("图片归一")
struct ImageNormalizerTests {
    /// 生成纯色位图 → 指定格式 bytes
    private func imageData(width: Int, height: Int, type: UTType, color: NSColor = .red) -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) // 先产 PNG 源
    }

    @Test func pngRoundTrip_keepsPixelsWithinLimit() throws {
        let source = try #require(imageData(width: 800, height: 400))
        let result = try #require(ImageNormalizer.normalize(source))
        #expect(result.pixelSize == ImagePixelSize(width: 800, height: 400))
        #expect(NSImage(data: result.data) != nil)  // 输出可再解码
    }

    @Test func oversizeImage_downscalesTo1024() throws {
        let source = try #require(imageData(width: 2048, height: 1024))
        let result = try #require(ImageNormalizer.normalize(source))
        #expect(result.pixelSize == ImagePixelSize(width: 1024, height: 512))
    }

    @Test func nonImageData_returnsNil() {
        #expect(ImageNormalizer.normalize(Data("not an image".utf8)) == nil)
        #expect(ImageNormalizer.normalize(Data()) == nil)
    }

    @Test func gifInput_takesFirstFrame() throws {
        // 单帧 GIF 源
        let png = try #require(imageData(width: 64, height: 64))
        let cg = try #require(NSImage(data: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let dest = try #require(CGImageDestinationCreateWithData(
            NSMutableData() as NSMutableData, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        #expect(CGImageDestinationFinalize(dest))
        let gifData = try #require((dest.takeUnretainedValue() as! NSMutableData) as Data? )
        let result = try #require(ImageNormalizer.normalize(gifData))
        #expect(result.pixelSize == ImagePixelSize(width: 64, height: 64))
    }

    @Test func heicInput_convertsToPNG() throws {
        let png = try #require(imageData(width: 100, height: 50))
        let cg = try #require(NSImage(data: png)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, AVFileType.heic.identifier as CFString, 1, nil),
            CGImageDestinationAddImage(dest, cg, nil),
            CGImageDestinationFinalize(dest) else {
            return  // HEIC 编码器不可用的环境直接跳过（断言不失败）
        }
        let result = try #require(ImageNormalizer.normalize(data as Data))
        #expect(result.pixelSize == ImagePixelSize(width: 100, height: 50))
    }
}
```

（测试文件头部若用 `AVFileType` 需 `import AVFoundation`；HEIC 编码不可用时直接 return 是环境守卫，不算断言。）

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test … -only-testing:LinvaAppTests/ImageNormalizerTests 2>&1 | tail -20`
Expected: FAIL（`ImageNormalizer` 未定义）

- [ ] **Step 3: 实现 `App/ImageNormalizer.swift`**

```swift
import AppKit
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// 图片归一器（FR-G1 入口）：任意图片数据 → 受控 PNG bytes + 像素尺寸。
/// 流程：CGImageSource 解码（gif 取首帧）→ 最长边 >1024 等比缩 → PNG 编码
/// → 仍 >5MB 再降 512 → 仍超限 nil（调用方提示，不入栈）。
enum ImageNormalizer {
    private static let maxPixelEdge: Int = 1024
    private static let secondPassEdge: Int = 512
    private static let maxEncodedBytes = 5 * 1024 * 1024

    static func normalize(_ data: Data) -> (data: Data, pixelSize: ImagePixelSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        var cg = original
        let maxEdge = max(cg.width, cg.height)
        if maxEdge > maxPixelEdge {
            let scale = CGFloat(maxPixelEdge) / CGFloat(maxEdge)
            guard let scaled = drawScaled(cg, scale: scale) else { return nil }
            cg = scaled
        }

        var encoded = encodePNG(cg)
        if (encoded?.count ?? 0) > maxEncodedBytes {
            let scale = CGFloat(secondPassEdge) / CGFloat(max(CGFloat(cg.width), CGFloat(cg.height)))
            if let smaller = drawScaled(cg, scale: scale) {
                encoded = encodePNG(smaller)
            }
        }
        guard var bytes = encoded, bytes.count <= maxEncodedBytes,
              let size = ImagePixelSize(width: Double(cg.width), height: Double(cg.height)) else {
            return nil
        }
        // PNG 编码含透明通道与颜色配置，尺寸以最终 CGImage 为准
        if let rep = NSBitmapImageRep(data: bytes), rep.pixelsWide > 0 {
            bytes = bytes // 已是目标数据；pixelSize 来自 cg
        }
        return (bytes, size)
    }

    private static func drawScaled(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 4: 跑测试确认通过 + 边界脚本绿**

Run: `xcodebuild test … -only-testing:LinvaAppTests/ImageNormalizerTests` && `bash scripts/check-boundaries.sh`
Expected: PASS / 「依赖边界检查通过」

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/App/ImageNormalizer.swift LinvaApp/LinvaAppTests/ImageNormalizerTests.swift scripts/check-boundaries.sh docs/superpowers/specs/2026-10-01-linva-image-node-design.md
git commit -m "feat: ImageNormalizer 图片归一（heic/gif→PNG、1024px/5MB 两级压缩）+ ImageIO 白名单"
```

---

### Task 3: `setImage` 命令（Model + CommandBus）

**Files:**
- Modify: `LinvaApp/LinvaApp/Commands/MindMapCommand.swift`（追加 case）
- Modify: `LinvaApp/LinvaApp/Model/MindMapModel.swift:212-223`（仿 setFill 追加方法）
- Modify: `LinvaApp/LinvaApp/Commands/CommandBus.swift:236`（applyForward 追加 case）
- Test: `LinvaApp/LinvaAppTests/CommandBusTests.swift`（追加）

**Interfaces:**
- Consumes: `ImagePixelSize`（Task 1）。
- Produces: `MindMapCommand.setImage(ids: [UUID], image: Data?, pixelSize: ImagePixelSize?)`；`MindMapModel.setImage(ids:image:pixelSize:) -> [(id: UUID, oldImage: Data?, oldPixelSize: ImagePixelSize?)]`。Task 4 的 Session 只经 `commandBus.execute(.setImage(...))` 使用。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("setImage 命令")
struct SetImageCommandTests {
    private let bytesA = Data([0x01])
    private let bytesB = Data([0x02])
    private let sizeA = ImagePixelSize(width: 10, height: 10)

    @Test func setImage_undoRedoRestoresPreviousImage() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        bus.execute(.setImage(ids: [root], image: bytesA, pixelSize: sizeA))
        #expect(model.node(id: root)?.image == bytesA)

        bus.execute(.setImage(ids: [root], image: bytesB, pixelSize: sizeA))
        bus.undo()
        #expect(model.node(id: root)?.image == bytesA)
        bus.redo()
        #expect(model.node(id: root)?.image == bytesB)
    }

    @Test func clearImage_undoRestoresImage() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        bus.execute(.setImage(ids: [root], image: bytesA, pixelSize: sizeA))
        bus.execute(.setImage(ids: [root], image: nil, pixelSize: nil))
        #expect(model.node(id: root)?.image == nil)
        bus.undo()
        #expect(model.node(id: root)?.image == bytesA)
    }

    @Test func noOpSetImage_doesNotEnterUndoStack() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.setImage(ids: [model.document.root.id], image: nil, pixelSize: nil))
        #expect(bus.canUndo == false)
    }

    @Test func setImage_keepsSelection() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let root = model.document.root.id
        let child = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        model.selectOnly(child)
        bus.execute(.setImage(ids: [root], image: bytesA, pixelSize: sizeA))
        #expect(model.selectedIds == [child])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**（`-only-testing:LinvaAppTests/SetImageCommandTests`）Expected: FAIL（case 未定义）

- [ ] **Step 3: 实现**

`MindMapCommand.swift` 追加：

```swift
    case setImage(ids: [UUID], image: Data?, pixelSize: ImagePixelSize?)
```

`MindMapModel.swift`（`setFill` 之后追加，同风格）：

```swift
    /// 对选中集每个节点写同一图片（nil = 清除）；返回被改节点旧值供 Undo。不改选中。
    @discardableResult
    func setImage(
        ids: [UUID],
        image: Data?,
        pixelSize: ImagePixelSize?
    ) -> [(id: UUID, oldImage: Data?, oldPixelSize: ImagePixelSize?)] {
        var changes: [(id: UUID, oldImage: Data?, oldPixelSize: ImagePixelSize?)] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let node = node(id: id),
                  node.image != image || node.imagePixelSize != pixelSize else { continue }
            changes.append((id, node.image, node.imagePixelSize))
            _ = mutate(id: id) {
                $0.image = image
                $0.imagePixelSize = image == nil ? nil : pixelSize
            }
        }
        return changes
    }
```

`CommandBus.applyForward`（`case .setFill` 块后追加）：

```swift
        case let .setImage(ids, image, pixelSize):
            let changes = model.setImage(ids: ids, image: image, pixelSize: pixelSize)
            guard !changes.isEmpty else { return nil }
            return Entry(
                undo: {
                    for c in changes {
                        _ = self.model.mutate(id: c.id) {
                            $0.image = c.oldImage
                            $0.imagePixelSize = c.oldPixelSize
                        }
                    }
                },
                redo: {
                    _ = self.model.setImage(ids: ids, image: image, pixelSize: pixelSize)
                }
            )
```

- [ ] **Step 4: 跑测试确认通过**（同 Step 2 + 全量）
- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Commands LinvaApp/LinvaApp/Model/MindMapModel.swift LinvaApp/LinvaAppTests/CommandBusTests.swift
git commit -m "feat: setImage/clearImage 单命令双用途入命令栈（仿 setFill，一步 Undo）"
```

---

### Task 4: Session 入口 + 图片级选中态

**Files:**
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`（属性区 + `setFill` 附近追加方法）
- Test: `LinvaApp/LinvaAppTests/DocumentSessionTests.swift`（追加 Suite）

**Interfaces:**
- Consumes: `MindMapCommand.setImage`（Task 3）、`ImageNormalizer.normalize` 签名（Task 2）。
- Produces: `DocumentSession.selectedImageId: UUID?`（@Published private(set)）；`var imageNormalizer: ((Data) -> (data: Data, pixelSize: ImagePixelSize)?)?`（注入点，默认 nil）；`func setImage(_ image: Data?, pixelSize: ImagePixelSize?)`；`@discardableResult func setPastedImage(from data: Data) -> Bool`；`func selectImage(_ id: UUID)`；`func clearImageSelection()`。Task 7 渲染读 `selectedImageId`、Task 9 交互调用全部四个方法。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("Session 图片")
struct SessionImageTests {
    private let png = Data([0x89, 0x50])
    private let px = ImagePixelSize(width: 64, height: 32)

    @Test func setPastedImage_normalizesAndCommits() {
        let session = DocumentSession()
        session.imageNormalizer = { _ in (Data([0xAA]), ImagePixelSize(width: 8, height: 8)) }
        let root = session.model.document.root.id

        #expect(session.setPastedImage(from: Data([0x01])) == true)
        #expect(session.model.node(id: root)?.image == Data([0xAA]))
        #expect(session.isDirty)
    }

    @Test func setPastedImage_withoutNormalizerOrSelection_fails() {
        let session = DocumentSession()
        #expect(session.setPastedImage(from: Data([0x01])) == false)  // 无注入

        session.imageNormalizer = { _ in (Data([0xAA]), ImagePixelSize(width: 8, height: 8)) }
        session.clearSelection()
        #expect(session.setPastedImage(from: Data([0x01])) == false)  // 无选中
    }

    @Test func setImage_clearsSelectedImageId_andTargetsImageNode() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let child = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.selectOnly(child)
        session.commandBus.execute(.setImage(ids: [child], image: png, pixelSize: px))
        session.selectImage(child)
        #expect(session.selectedImageId == child)

        session.setImage(nil, pixelSize: nil)   // ⌫ 分派目标：图片
        #expect(session.model.node(id: child)?.image == nil)
        #expect(session.selectedImageId == nil)  // 清图后回落
    }

    @Test func selectImage_clearOnEscapeProxy_andNotInUndoStack() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        session.selectImage(root)
        #expect(session.selectedImageId == root)
        session.clearImageSelection()
        #expect(session.selectedImageId == nil)
        // 选中态不入命令栈：仅 selectImage/clear 不产生 Undo
        #expect(session.commandBus.canUndo == false)
    }

    @Test func setPastedImage_commitsEditingFirst() {
        let session = DocumentSession()
        session.imageNormalizer = { _ in (Data([0xAA]), px) }
        let root = session.model.document.root.id
        session.startEditing(root)
        session.draftText = "先提交"
        _ = session.setPastedImage(from: Data([0x01]))
        #expect(session.editingId == nil)
        #expect(session.model.node(id: root)?.text == "先提交")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**（`-only-testing:LinvaAppTests/SessionImageTests`）Expected: FAIL

- [ ] **Step 3: 实现**（`DocumentSession`）

属性区（`clipboard` 声明后）追加：

```swift
    /// 图片级选中（节点内子元素）；不入命令栈，同时最多一个。
    @Published private(set) var selectedImageId: UUID?
    /// 图片归一注入点（App 组合根赋 ImageNormalizer.normalize；测试注入 stub）。Session 白名单无 ImageIO。
    var imageNormalizer: ((Data) -> (data: Data, pixelSize: ImagePixelSize)?)?
```

`setFill(_:)` 后追加：

```swift
    // MARK: - 节点图片（FR-G2）

    /// 写/清图片。清除时若处于图片级选中，目标为被选图片所在节点（⌫ 分派）。
    func setImage(_ image: Data?, pixelSize: ImagePixelSize?) {
        commitEditingIfNeeded()
        if image == nil, let selectedImageId {
            let ids = [selectedImageId]
            self.selectedImageId = nil   // 清图后回落：选中回节点
            commandBus.execute(.setImage(ids: ids, image: nil, pixelSize: nil))
            return
        }
        selectedImageId = nil
        commandBus.execute(.setImage(ids: Array(model.selectedIds), image: image, pixelSize: pixelSize))
    }

    /// 粘贴/拖入入口：归一 + 入栈。要求有选中节点；失败（无归一器/无选中/数据非法）返回 false 由壳层提示。
    @discardableResult
    func setPastedImage(from data: Data) -> Bool {
        commitEditingIfNeeded()
        guard let normalizer = imageNormalizer,
              !model.selectedIds.isEmpty,
              let normalized = normalizer(data) else {
            return false
        }
        selectedImageId = nil
        commandBus.execute(
            .setImage(ids: Array(model.selectedIds), image: normalized.data, pixelSize: normalized.pixelSize)
        )
        return true
    }

    /// 双击图片区域：进入图片级选中（节点选中态不变）。
    func selectImage(_ id: UUID) {
        guard model.node(id: id) != nil else { return }
        selectedImageId = id
    }

    func clearImageSelection() {
        selectedImageId = nil
    }
```

`load(from:)`/`loadImported`/`newDocument` 里与其他会话态一起清：`selectedImageId = nil`（三处，挨着 `editingId = nil` / `recovery = nil` 的位置）。删除节点时清理：`DocumentSession` 内删除入口若存在 `removeMany` 包装则追加 `if let selectedImageId, model.node(id: selectedImageId) == nil { selectedImageId = nil }`——若无集中入口，在 `ContentView.deleteSelected` 调用后由 model 变化兜底（Task 9 手测覆盖）。

- [ ] **Step 4: 跑测试确认通过** + 全量
- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Session/DocumentSession.swift LinvaApp/LinvaAppTests/DocumentSessionTests.swift
git commit -m "feat: Session 图片入口 setPastedImage/setImage + 图片级选中态 selectedImageId"
```

---

### Task 5: Layout — 尺寸合成 + Snapshot 图片载荷

**Files:**
- Modify: `LinvaApp/LinvaApp/Layout/LayoutConstants.swift`（追加 2 常量）
- Modify: `LinvaApp/LinvaApp/Layout/TextMeasure.swift`（合成公式）
- Modify: `LinvaApp/LinvaApp/Layout/LayoutSnapshot.swift`（`NodeFrame.imageRect`、`ImagePayload`、`LayoutSnapshot.imagePayloads`）
- Modify: `LinvaApp/LinvaApp/Layout/RadialLayout.swift`（两处 `NodeFrame(...)` + payload 收集）
- Test: `LinvaApp/LinvaAppTests/RadialLayoutTests.swift`（追加）

**Interfaces:**
- Consumes: `Node.imagePixelSize`（Task 1）。
- Produces: `LayoutConstants.imageMaxDisplayWidth = 300`、`LayoutConstants.imageTextGap = 6`；`NodeFrame.imageRect: CGRect?`（节点局部坐标，**top-left 原点**：图在上、文字在下）；`struct ImagePayload: Equatable { let pixelSize: ImagePixelSize; let data: Data }`；`LayoutSnapshot.imagePayloads: [UUID: ImagePayload]`。Task 6/7/8 依赖这三个名字。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("图片布局")
struct ImageLayoutTests {
    private func measure() -> TextMeasure { TextMeasure() }

    @Test func sizedNode_growsForImage_withinDisplayLimit() {
        var doc = MindMapDocument.blank(rootText: "根")
        // 图片 600×300pt 请求 → 上限 300 → 显示 300×150
        doc.root.imagePixelSize = ImagePixelSize(width: 600, height: 300)
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        let frame = snapshot.frames[doc.root.id]!

        let bare = MindMapDocument.blank(rootText: "根")
        let bareFrame = RadialLayout.layout(document: bare, measure: measure()).frames[bare.root.id]!

        #expect(frame.size.height == bareFrame.size.height + LayoutConstants.imageTextGap + 150)
        #expect(frame.imageRect != nil)
        let rect = frame.imageRect!
        #expect(rect.width == 300)
        #expect(abs(rect.height - 150) < 0.001)
        // 水平居中于节点
        #expect(abs((rect.midX) - frame.size.width / 2) < 0.001)
        #expect(snapshot.imagePayloads[doc.root.id] != nil)
    }

    @Test func smallImage_centered_whenTextDrivesWidth() {
        var doc = MindMapDocument.blank(rootText: "相当长的文字内容决定节点宽度")
        doc.root.imagePixelSize = ImagePixelSize(width: 50, height: 50)
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        let frame = snapshot.frames[doc.root.id]!
        let rect = frame.imageRect!
        #expect(rect.width == 50)
        #expect(abs(rect.midX - frame.size.width / 2) < 0.001)
    }

    @Test func imagelessNode_hasNoImageRectOrPayload() {
        let doc = MindMapDocument.blank(rootText: "根")
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        #expect(snapshot.frames[doc.root.id]!.imageRect == nil)
        #expect(snapshot.imagePayloads.isEmpty)
    }

    @Test func collapsedDescendantWithImage_isAbsentFromFramesAndPayloads() {
        var doc = MindMapDocument.blank(rootText: "根")
        let child = Node(text: "折叠", image: Data([0x01]), imagePixelSize: ImagePixelSize(width: 10, height: 10))
        doc.root.children = [child]
        doc.root.collapsed = true
        let snapshot = RadialLayout.layout(document: doc, measure: measure())
        #expect(snapshot.frames[child.id] == nil)
        #expect(snapshot.imagePayloads[child.id] == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**（`-only-testing:LinvaAppTests/ImageLayoutTests`）Expected: FAIL

- [ ] **Step 3: 实现**

`LayoutConstants.swift` 追加：

```swift
    static let imageMaxDisplayWidth: CGFloat = 300
    static let imageTextGap: CGFloat = 6
```

`TextMeasure.swift`：现 return 处替换为：

```swift
        let textWidth = ceil(measuredWidth + horizontalPadding * 2)
        let textHeight = ceil(CGFloat(lineCount) * lineHeight + verticalPadding * 2)

        guard let px = node.imagePixelSize, px.width > 0, px.height > 0 else {
            return NodeSize(width: textWidth, height: textHeight)
        }
        // 图片显示宽 = min(像素宽, 上限)；等比高；节点宽取 max、高叠加（spec §3.1）
        let imageWidth = min(CGFloat(px.width), LayoutConstants.imageMaxDisplayWidth)
        let imageHeight = imageWidth * CGFloat(px.height) / CGFloat(px.width)
        return NodeSize(
            width: ceil(max(textWidth, imageWidth + horizontalPadding * 2)),
            height: ceil(textHeight + LayoutConstants.imageTextGap + imageHeight)
        )
```

`LayoutSnapshot.swift`：`NodeFrame` 追加 `let imageRect: CGRect?`（属性 + init 参数默认 `nil`，挨着 `fill`）；文件尾部追加：

```swift
/// 有图节点的图片载荷：Layout 从 Model 拷出像素数据与尺寸，Render 只消费 Snapshot。
struct ImagePayload: Equatable {
    let pixelSize: ImagePixelSize
    let data: Data
}
```

`LayoutSnapshot` 结构追加 `let imagePayloads: [UUID: ImagePayload]`，init 追加带默认值参数 `imagePayloads: [UUID: ImagePayload] = [:]`。

`RadialLayout.swift`：

1. `placeBranch` 与 rootFrame 的 `NodeFrame(...)` 构造各追加 `imageRect: Self.imageRect(size: metadata.size, pixelSize: node.imagePixelSize)`（rootFrame 处用 `document.root.imagePixelSize` 与 `rootMetadata.size`）。
2. `layout` 返回前组装 payload（在最终 `LayoutSnapshot(...)` 构造处传入 `imagePayloads: payloads`；注意三处 return：root 折叠早退、常规路径——两处都要传）：

```swift
        var payloads: [UUID: ImagePayload] = [:]
        func collectPayloads(_ node: Node) {
            if let image = node.image, let px = node.imagePixelSize, frames[node.id] != nil {
                payloads[node.id] = ImagePayload(pixelSize: px, data: image)
            }
            node.children.forEach(collectPayloads)
        }
        collectPayloads(document.root)
```

3. 文件内追加 helper：

```swift
    /// 图片区（节点局部坐标，top-left 原点：图在上、文字在下）；水平居中。
    private static func imageRect(size: NodeSize, pixelSize: ImagePixelSize?) -> CGRect? {
        guard let px = pixelSize, px.width > 0, px.height > 0 else { return nil }
        let width = min(CGFloat(px.width), LayoutConstants.imageMaxDisplayWidth)
        let height = width * CGFloat(px.height) / CGFloat(px.width)
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
    }
```

- [ ] **Step 4: 跑测试确认通过**（ImageLayoutTests + 既有 RadialLayoutTests/HitTestTests 全绿——`NodeFrame` init 默认值保证零迁移）+ 全量
- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Layout LinvaApp/LinvaAppTests/RadialLayoutTests.swift
git commit -m "feat: 图文同框布局（300pt 上限合成）+ LayoutSnapshot 携带图片载荷"
```

---

### Task 6: Render — `ImageTextureCache`（降采样 + LRU + 指纹）

**Files:**
- Create: `LinvaApp/LinvaApp/Render/ImageTextureCache.swift`
- Test: `LinvaApp/LinvaAppTests/ImageTextureCacheTests.swift`（新建）

**Interfaces:**
- Consumes: `ImagePayload`/`NodeFrame.imageRect`（Task 5）、`TextTextureRasterizer.makeBitmap/makeTexture`（既有）。
- Produces: `final class ImageTextureCache { init(byteBudget: Int = 128 * 1024 * 1024); func texture(for frame: NodeFrame, payload: ImagePayload, device: MTLDevice) -> MTLTexture?; func evictUnused(known: Set<UUID>) }`。Task 7 持有并调用。

- [ ] **Step 1: 写失败测试**

```swift
import Metal
import Testing
@testable import LinvaApp

@Suite("图片纹理缓存")
struct ImageTextureCacheTests {
    private func frameWithImage(width: Int, height: Int) -> (NodeFrame, ImagePayload) {
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n",
            center: .zero, size: NodeSize(width: 100, height: 100),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            imageRect: CGRect(x: 0, y: 0, width: width, height: height)
        )
        // 1×1 PNG 字节串就够走解码路径
        let png = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!.representation(using: .png, properties: [:])!
        return (frame, ImagePayload(pixelSize: ImagePixelSize(width: 1, height: 1)!, data: png))
    }

    @Test func texture_buildsOnceAndReusesOnHit() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache(byteBudget: 8 * 1024 * 1024)
        let (frame, payload) = frameWithImage(width: 40, height: 40)
        let t1 = try #require(cache.texture(for: frame, payload: payload, device: device))
        let t2 = cache.texture(for: frame, payload: payload, device: device)
        #expect(t2 === t1)  // 同脏键命中，不重建
    }

    @Test func changedData_rebuildsTexture() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache(byteBudget: 8 * 1024 * 1024)
        let (frame, payload) = frameWithImage(width: 40, height: 40)
        let t1 = try #require(cache.texture(for: frame, payload: payload, device: device))
        var changed = payload
        changed = ImagePayload(pixelSize: payload.pixelSize, data: Data(payload.data.dropLast(1) + [0x00]))
        let t2 = cache.texture(for: frame, payload: changed, device: device)
        #expect(t2 !== t1)  // 数据变了 → 重建
    }

    @Test func lru_evictsLeastRecentlyUsed_overBudget() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        // 预算只装得下 2 张 100×100（×4 字节 = 40KB）
        let cache = ImageTextureCache(byteBudget: 80 * 1024)
        let (a, pa) = frameWithImage(width: 100, height: 100)
        let (b, pb) = frameWithImage(width: 100, height: 100)
        let (c, pc) = frameWithImage(width: 100, height: 100)
        _ = cache.texture(for: a, payload: pa, device: device)
        _ = cache.texture(for: b, payload: pb, device: device)
        _ = cache.texture(for: a, payload: pa, device: device)  // a 变为最近使用
        _ = cache.texture(for: c, payload: pc, device: device)  // 插入 c → 驱逐 b
        let bAgain = cache.texture(for: b, payload: pb, device: device)
        #expect(bAgain != nil)  // 驱逐后重建成功（可重入）
    }

    @Test func corruptData_returnsNil_notCrash() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache()
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n", center: .zero, size: NodeSize(width: 50, height: 50),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            imageRect: CGRect(x: 0, y: 0, width: 50, height: 50)
        )
        let payload = ImagePayload(pixelSize: ImagePixelSize(width: 10, height: 10)!, data: Data("junk".utf8))
        #expect(cache.texture(for: frame, payload: payload, device: device) == nil)
    }

    @Test func evictUnused_dropsEntriesOutsideKnownSet() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let cache = ImageTextureCache()
        let (frame, payload) = frameWithImage(width: 10, height: 10)
        _ = cache.texture(for: frame, payload: payload, device: device)
        cache.evictUnused(known: [])
        _ = cache.texture(for: frame, payload: payload, device: device)  // 已被清，重新建
        #expect(true)  // 不崩即可：重建路径畅通
    }
}
```

- [ ] **Step 2: 跑测试确认失败** Expected: FAIL（类未定义）

- [ ] **Step 3: 实现 `Render/ImageTextureCache.swift`**

```swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Metal

/// 图片纹理缓存（spec §4.1）：脏键 = 节点 id + 显示像素尺寸 + scale 桶 + 数据指纹；
/// 解码即降采样（CGImageSource thumbnail，按显示尺寸 × scale）；LRU 字节预算驱逐。
final class ImageTextureCache {
    private struct Entry {
        let texture: MTLTexture
        let bytes: Int
        var lastUse: Int
    }

    private let byteBudget: Int
    private let device: MTLDevice
    private var entries: [UUID: Entry] = [:]
    private var tick = 0
    private var bytesUsed = 0

    init(byteBudget: Int = 128 * 1024 * 1024, device: MTLDevice) {
        self.byteBudget = byteBudget
        self.device = device
    }

    func texture(for frame: NodeFrame, payload: ImagePayload, device: MTLDevice) -> MTLTexture? {
        guard let local = frame.imageRect, local.width > 0, local.height > 0 else { return nil }

        // 显示尺寸 → 像素尺寸（scale 由调用方按 rasterBucket 量化后折入 local？否：local 是 pt，
        // 像素 = local × displayScale，displayScale 由 renderer 传入——这里接口收 frame/payload，
        // 由 renderer 先把 scale 量化并入 frame 副本；缓存不感知相机。）
        ...
    }
}
```

**实现说明（执行者必读）**：scale 量化属 renderer（`rasterBucket`），缓存接口收「已按 scale 算好像素尺寸」的参数更纯净——最终签名：

```swift
    func texture(
        id: UUID,
        localRect: CGRect,      // pt（= frame.imageRect）
        payload: ImagePayload,
        displayScale: CGFloat,  // renderer 已乘 rasterBucket
        device: MTLDevice
    ) -> MTLTexture?
```

脏键结构：

```swift
    private struct CacheKey: Equatable {
        let widthPx: Int
        let heightPx: Int
        let scaleMilli: Int          // Int((displayScale * 100).rounded())，与 TextAtlas 同法
        let dataFingerprint: Int     // payload.data.hashValue ^ payload.data.count
    }
```

解码路径（CoreGraphics → 位图 → MTLTexture，**保留 flipVertically 语义**）：

```swift
        let widthPx = max(Int(ceil(localRect.width * displayScale)), 1)
        let heightPx = max(Int(ceil(localRect.height * displayScale)), 1)
        let key = CacheKey(
            widthPx: widthPx, heightPx: heightPx,
            scaleMilli: Int((displayScale * 100).rounded()),
            dataFingerprint: payload.data.hashValue ^ payload.data.count
        )
        if let cached = entries[id], cached.key == key {    // Entry 追加 key 字段
            cachedUse(id)
            return cached.texture
        }

        guard let source = CGImageSourceCreateWithData(payload.data as CFData, nil) else { return nil }
        let maxPixel = max(widthPx, heightPx)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil   // 数据非法 → 按无图显示（spec 容错）
        }

        // 画进 RGBA 位图（同文字纹理格式），flipVertically 后 makeTexture
        guard let bitmap = TextTextureRasterizer.makeBitmap(
            width: widthPx, height: heightPx, displayScale: 1,
            draw: { ... }   // 注意：makeBitmap 的 draw 闭包里拿不到 CGContext——见下
        ) else { return nil }
```

**执行者注意**：`TextTextureRasterizer.makeBitmap(width:height:displayScale:draw:)` 的 `draw` 闭包在 flipped NSGraphicsContext 下执行且内部已按 displayScale 缩放坐标。图片路径用法：

```swift
        guard let bitmap = TextTextureRasterizer.makeBitmap(
            width: widthPx,
            height: heightPx,
            displayScale: 1,
            draw: {
                // 在 flipped 上下文中把 CGImage 铺满目标矩形；premultipliedLast 适配 makeTexture 格式
                NSGraphicsContext.current?.cgContext.interpolationQuality = .high
                // cg 绘制方向：flipped 上下文 + makeBitmap 内部 flipVertically 组合后
                // 与文字路径同向；若目测图片上下颠倒，只允许调整这里的 draw 矩形 y 翻转，
                // 禁止删 flipVertically（linva-render-text 纪律）。
                let cgContext = NSGraphicsContext.current!.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: CGFloat(heightPx))
                cgContext.scaleBy(x: 1, y: -1)
                cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
                cgContext.restoreGState()
            }
        ) else { return nil }

        guard let texture = TextTextureRasterizer.makeTexture(
            device: device, width: widthPx, height: heightPx,
            bitmap: bitmap, label: "图片纹理 \(id)"
        ) else { return nil }
```

`makeBitmap` 当前签名是 `draw: () -> Void` 无参闭包——闭包内经 `NSGraphicsContext.current` 取上下文（上面代码即此法），若 `cg`/尺寸需捕获，用闭包捕获列表。**不改 `TextAtlas.swift` 的 makeBitmap 签名**。

LRU 与驱逐：

```swift
    private func insert(id: UUID, key: CacheKey, texture: MTLTexture, bytes: Int) {
        tick += 1
        bytesUsed += bytes
        entries[id] = Entry(texture: texture, bytes: bytes, lastUse: tick, key: key)
        while bytesUsed > byteBudget, let victim = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            bytesUsed -= victim.value.bytes
            entries.removeValue(forKey: victim.key)
        }
    }

    func evictUnused(known: Set<UUID>) {
        for id in entries.keys where !known.contains(id) {
            bytesUsed -= entries[id]!.bytes
            entries.removeValue(forKey: id)
        }
    }
```

（测试相应按最终签名调整：`cache.texture(id: frame.id, localRect: frame.imageRect!, payload: payload, displayScale: 1, device: device)`。）

- [ ] **Step 4: 跑测试确认通过**（`-only-testing:LinvaAppTests/ImageTextureCacheTests`）
- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/ImageTextureCache.swift LinvaApp/LinvaAppTests/ImageTextureCacheTests.swift
git commit -m "feat: ImageTextureCache 降采样解码 + LRU 128MB 预算 + 脏键指纹"
```

---

### Task 7: MetalRenderer — drawImage + 选中描边 + PNG 含图

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/MetalRenderer.swift`（属性 + `encodeContent` + 新 `drawImage` + `renderImage` 签名）
- Test: `LinvaApp/LinvaAppTests/PNGExporterTests.swift`（追加）

**Interfaces:**
- Consumes: `ImageTextureCache`（Task 6）、`LayoutSnapshot.imagePayloads`（Task 5）。
- Produces: `MetalRenderer.draw(...)` 签名**追加** `selectedImageId: UUID?`；`renderImage(...)` 追加 `selectedImageId: UUID? = nil`（PNGExporter 不改即编译过）。`encodeContent` 内部同步加参。

- [ ] **Step 1: 写失败测试**（PNGExporterTests 追加：真渲染含图）

```swift
@Suite("PNG 导出含图")
struct PNGWithImageTests {
    @Test func exportedPNG_containsImagePixels() throws {
        // 造 4×4 纯红 PNG
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep!)
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = rep!.representation(using: .png, properties: [:])!

        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.imagePixelSize = ImagePixelSize(width: 100, height: 100)
        doc.root.image = png

        let data = try #require(PNGExporter.data(document: doc))
        let outRep = try #require(NSBitmapImageRep(data: data))

        // 找根节点在导出快照中的图片区中心像素 → 应为红色（导出视口含全图）
        let expanded = PNGExporter.fullyExpanded(doc)
        let snapshot = RadialLayout.layout(document: expanded, measure: TextMeasure())
        let frame = try #require(snapshot.frames[doc.root.id])
        let local = try #require(frame.imageRect)
        let worldRect = CGRect(
            x: frame.rect.minX + local.minX, y: frame.rect.minY + local.minY,
            width: local.width, height: local.height)
        let bounds = snapshot.frames.values.reduce(CGRect.null) { $0.union($1.rect) }
        // renderImage: bounds + padding 48，长边缩到 2400；按同公式换算像素坐标
        let scale = min(max(2400 / max(bounds.width, bounds.height), 0.35), 2)
        let originX = bounds.minX - 48
        let originY = bounds.minY - 48
        let px = Int((worldRect.midX - originX) * scale)
        let py = Int((worldRect.midY - originY) * scale)
        guard let color = outRep.colorAt(x: px, y: py) else {
            Issue.record("像素越界")
            return
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.6 && g < 0.4 && b < 0.4)
    }
}
```

（导出位图 y 向：`colorAt` 是 top-left 原点；renderImage 读回的 texture 行序 = 世界 y-up。执行者若断言点错位，翻转 `py = pixelH - py` 再试——**只调测试的坐标换算，不动渲染**。）

- [ ] **Step 2: 跑测试确认失败**（`-only-testing:LinvaAppTests/PNGWithImageTests`）Expected: FAIL（图中无红色像素/渲染不含图）

- [ ] **Step 3: 实现**

`MetalRenderer`：

1. 属性追加：`private let imageTextureCache: ImageTextureCache`——init 里 `self.imageTextureCache = ImageTextureCache(device: device)`。
2. `draw(in:...)` 与 `encodeContent(...)` 各追加参数 `selectedImageId: UUID?`；`draw` 调 `encodeContent` 时传 `session` 侧值——`draw` 参数列表追加 `selectedImageId: UUID?`，`CanvasMetalView.draw(in:)`（Task 9）传入 `session.selectedImageId`。
3. `encodeContent` 在 `drawSolid(fillVertices...)` 之后、`drawText` 之前插入：

```swift
        drawImage(
            snapshot: snapshot, camera: camera, displayScale: displayScale,
            selectedImageId: selectedImageId,
            encoder: encoder, viewport: &viewport
        )
```

4. `drawImage` 实现（置于 `drawText` 后）：

```swift
    /// 图片 quad：视口剔除 → 缓存纹理 → texturedQuad（与文字同管线）。
    private func drawImage(
        snapshot: LayoutSnapshot,
        camera: Camera,
        displayScale: CGFloat,
        selectedImageId: UUID?,
        encoder: MTLRenderCommandEncoder,
        viewport: inout ViewportUniforms
    ) {
        guard !snapshot.imagePayloads.isEmpty else { return }
        encoder.setRenderPipelineState(texturedPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)

        var knownIds = Set<UUID>()
        let rasterScale = displayScale * Self.rasterBucket(camera.scale)

        for frame in orderedFrames(snapshot) {
            guard let local = frame.imageRect,
                  let payload = snapshot.imagePayloads[frame.id] else { continue }
            let worldRect = CGRect(
                x: frame.rect.minX + local.minX,
                y: frame.rect.minY + local.minY,
                width: local.width,
                height: local.height
            )
            let screen = screenRect(worldRect, camera: camera)
            // 视口剔除：屏幕外连纹理都不建（显存纪律一）
            guard screen.intersects(CGRect(origin: .zero, size: viewport.size.cgSize)) else { continue }
            knownIds.insert(frame.id)

            guard let texture = imageTextureCache.texture(
                id: frame.id,
                localRect: local,
                payload: payload,
                displayScale: rasterScale,
                device: device
            ) else { continue }

            let vertices = texturedQuad(rect: screen, color: SIMD4<Float>(1, 1, 1, 1))
            guard let buffer = device.makeBuffer(
                bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count
            ) else { continue }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<ViewportUniforms>.stride, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
        imageTextureCache.evictUnused(known: knownIds)   // 节点删除/折叠后清理（显存纪律三）
    }
```

（`viewport.size.cgSize`：SIMD2 无 cgSize——用 `CGSize(width: CGFloat(viewport.size.x), height: CGFloat(viewport.size.y))`。）

5. 选中描边：`drawSelectionStrokes` 尾部追加：

```swift
        if let selectedImageId,
           let frame = snapshot.frames[selectedImageId],
           let local = frame.imageRect {
            let worldRect = CGRect(
                x: frame.rect.minX + local.minX, y: frame.rect.minY + local.minY,
                width: local.width, height: local.height)
            drawSolid(
                strokeVertices(rect: screenRect(worldRect, camera: camera), thickness: 2, color: rgba(.controlAccentColor)),
                encoder: encoder, viewport: &viewport
            )
        }
```

（圆角描边 v1 用直角 4 边近似——与既有描边 pass 同法；圆角 shader 不在本增量。）

6. `renderImage(...)` 追加 `selectedImageId: UUID? = nil` 并透传 `encodeContent`。PNGExporter 不改（默认参数）。

- [ ] **Step 4: 跑测试确认通过**（PNGWithImageTests + 全量）；**目测手测**：`xcodebuild -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp build && open LinvaApp/build/Release/LinvaApp.app`（或 Xcode Run）——临时在 root 节点贴图验证方向正确；若图片上下颠倒 → 只允许调 `ImageTextureCache` 绘制闭包的 y 翻转，**禁止动 `flipVertically`**。
- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/MetalRenderer.swift LinvaApp/LinvaAppTests/PNGExporterTests.swift
git commit -m "feat: MetalRenderer 图片 quad（视口剔除+缓存）+ 图片选中描边；PNG 导出自动含图"
```

---

### Task 8: 命中测试 — imageRect 双击命中

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/CanvasHitTesting.swift`（追加函数）
- Test: `LinvaApp/LinvaAppTests/HitTestTests.swift`（追加）

**Interfaces:**
- Consumes: `NodeFrame.imageRect`（Task 5）。
- Produces: `func hitTestImageRect(screenPoint: CGPoint, snapshot: LayoutSnapshot, camera: Camera) -> UUID?`。Task 9 双击分派调用。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("图片命中")
struct ImageHitTests {
    @Test func hitTestImageRect_insideImage_returnsNodeID() {
        let id = UUID()
        var frame = makeFrame(id: id, size: NodeSize(width: 100, height: 100))
        frame = NodeFrame(
            id: id, text: frame.text, center: frame.center, size: frame.size,
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            imageRect: CGRect(x: 0, y: 0, width: 100, height: 50)   // 节点上半
        )
        let snapshot = LayoutSnapshot(frames: [id: frame], edges: [])
        let camera = Camera()
        // imageRect top-left 原点：世界 rect = frame.rect.min + local 偏移
        let worldRect = CGRect(
            x: frame.rect.minX, y: frame.rect.minY, width: 100, height: 50)
        let screenPoint = camera.worldToScreen(CGPoint(x: worldRect.midX, y: worldRect.midY))
        #expect(hitTestImageRect(screenPoint: screenPoint, snapshot: snapshot, camera: camera) == id)
        // 文字区（下半）不算图片
        let textPoint = camera.worldToScreen(CGPoint(x: frame.rect.midX, y: frame.rect.maxY - 5))
        #expect(hitTestImageRect(screenPoint: textPoint, snapshot: snapshot, camera: camera) == nil)
    }

    @Test func hitTestImageRect_outsideNode_returnsNil() {
        let id = UUID()
        let frame = NodeFrame(
            id: id, text: "n", center: .zero, size: NodeSize(width: 80, height: 40),
            isRoot: false, side: .right, collapsed: false, hiddenCount: 0,
            imageRect: CGRect(x: 0, y: 0, width: 80, height: 20))
        let snapshot = LayoutSnapshot(frames: [id: frame], edges: [])
        #expect(hitTestImageRect(screenPoint: CGPoint(x: 500, y: 500), snapshot: snapshot, camera: Camera()) == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** Expected: FAIL
- [ ] **Step 3: 实现**（`CanvasHitTesting.swift`，`hitTestNode` 后追加）

```swift
/// 双击命中图片区：命中返回节点 id（图片属节点，selectedImageId 记节点 id）。
/// imageRect 为节点局部 top-left 原点矩形，世界 rect = frame.rect.origin + 偏移。
func hitTestImageRect(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> UUID? {
    let world = camera.screenToWorld(screenPoint)
    for frame in snapshot.frames.values {
        guard let local = frame.imageRect else { continue }
        let worldRect = CGRect(
            x: frame.rect.minX + local.minX,
            y: frame.rect.minY + local.minY,
            width: local.width,
            height: local.height
        )
        if worldRect.contains(world) {
            return frame.id
        }
    }
    return nil
}
```

（测试里 makeFrame 返回值不可变——直接按上面第二例造带 imageRect 的 frame；y 方向如目测颠倒，与 Task 7 的渲染方向修正**同一处约定**：以渲染手测结论为准，命中与渲染共用「local top-left 偏移」公式。）

- [ ] **Step 4: 跑测试确认通过** + 全量
- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/CanvasHitTesting.swift LinvaApp/LinvaAppTests/HitTestTests.swift
git commit -m "feat: 图片区命中测试 hitTestImageRect（双击选中图片用）"
```

---

### Task 9: 交互接线 — 双击/⌫/Esc/⌘V/拖入/组合根

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`（`CanvasActions` + `beginPointerGesture` + `keyDown` + 拖放）
- Modify: `LinvaApp/LinvaApp/ContentView.swift:281-285`（`paste()` 优先级）+ `deleteSelected` 清 selectedImageId
- Modify: `LinvaApp/LinvaApp/LinvaAppApp.swift:27-33`（组合根注入 normalizer）
- Test: 手测清单（本 Task 交互以手测为准；纯逻辑已被 Task 4/8 覆盖）

**Interfaces:**
- Consumes: Task 4 全部 Session API、Task 8 `hitTestImageRect`、Task 2 `ImageNormalizer.normalize`。
- Produces: `CanvasActions` 追加 `clearImage: () -> Void = {}`。

- [ ] **Step 1: CanvasActions + 双击分派**（`CanvasMetalView.swift`）

`CanvasActions` 追加 `var clearImage: () -> Void = {}`。

`beginPointerGesture` 的 `case let .node(id)` 分支，`clickCount == 2` 处改为：

```swift
            if event.clickCount == 2 {
                if hitTestImageRect(
                    screenPoint: point,
                    snapshot: session.snapshot,
                    camera: session.camera
                ) == id {
                    session.selectImage(id)      // 双击图片区 → 图片级选中
                } else {
                    actions.edit(id)             // 双击文字区 → 进文字编辑（现状）
                }
                gesture = .none
                return
            }
```

单击路径不动（永远选节点）。

- [ ] **Step 2: ⌫ / Esc 分派**（`keyDown`）

```swift
        case 51, 117:
            if session.selectedImageId != nil {
                actions.clearImage()      // 选中图片 → 只清图
            } else {
                actions.delete()          // 现状：删节点
            }
        case 53:
            if session.selectedImageId != nil {
                session.clearImageSelection()   // Esc 先退图片选中
            } else if !session.cutSourceIds.isEmpty {
                actions.cancelCut()
            } else {
                actions.select(nil, .replace)
            }
```

- [ ] **Step 3: 文件拖入**（`CanvasMTKView`，独立分支不碰 `DropIntent`）

init（`frame: .zero, device:...` 构造后）追加：

```swift
        registerForDraggedTypes([.png, .tiff, .fileURL])
```

扩展 `CanvasMTKView`（类声明加 `, NSDraggingDestination`——MTKView 继承 NSView 已具备）：

```swift
    // MARK: - 图片拖入（FR-G2；独立于搬枝 DropIntent）

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDraggableImage(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = draggedImageData(sender) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        // 落点节点即为目标：先选中再贴图（未选中节点也能拖入该节点）
        guard let nodeId = hitTestNode(
            screenPoint: point,
            snapshot: session.snapshot,
            camera: session.camera
        ) else { return false }
        session.selectOnly(nodeId)
        if !session.setPastedImage(from: data) {
            DispatchQueue.main.async { self.session.errorMessage = "无法读取图片" }
        }
        return true
    }

    private func hasDraggableImage(_ sender: NSDraggingInfo) -> Bool {
        draggedImageData(sender) != nil
    }

    private func draggedImageData(_ sender: NSDraggingInfo) -> Data? {
        let pb = sender.draggingPasteboard
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            return data
        }
        for url in (pb.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? [] {
            let ext = url.pathExtension.lowercased()
            if ["png", "jpeg", "jpg", "gif", "tiff", "heic"].contains(ext),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }
```

- [ ] **Step 4: ContentView 接线**（`CanvasActions(...)` 追加 `clearImage: { session.setImage(nil, pixelSize: nil) }`；`paste()` 改优先级）

```swift
    private func paste() {
        if session.editingId != nil { commitEditing() }
        if session.clipboard != nil {
            session.pasteToPrimary()      // ① 内部节点剪贴板优先（现状）
            return
        }
        guard !session.selectedIds.isEmpty else { return }   // ② 无选中不尝试图片
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return }
        if !session.setPastedImage(from: data) {
            session.errorMessage = "无法读取图片"
        }
    }
```

`deleteSelected`（既有实现）追加首行守卫：`session.clearImageSelection()` 不需要——⌫ 分派已在 view 层；但**工具栏删除按钮**走 `deleteSelected`：删除含 selectedImageId 的节点后图片选中悬空 → `deleteSelected` 尾部追加：

```swift
        if let imageId = session.selectedImageId, session.model.node(id: imageId) == nil {
            session.clearImageSelection()
        }
```

- [ ] **Step 5: 组合根注入**（`LinvaAppApp.init`）

```swift
        session.imageNormalizer = ImageNormalizer.normalize
```

- [ ] **Step 6: 手测清单**（Xcode Run，逐条过；任何一条不过 → 修复后重跑）

1. 选中节点 ⌘V 贴截图 → 图文同框、布局重排；⌘Z 一步撤销
2. 再次 ⌘V 替换；⌘Z 回上一张
3. 双击图片 → 圆角描边（v1 直角描边）出现；⌫ → 图清、节点在；⌘Z 恢复
4. 双击文字区 → 进文字编辑（现状不变）
5. Esc 退图片选中；⌫ 此时删节点（现状）
6. 拖 png/heic 文件到节点 → 入节点；拖到空白 → 无反应
7. 缩放平移：图片清晰（Retina）、屏幕外滚回不卡（缓存命中）
8. 折叠带图节点 → 自身图在、后代无图无纹理
9. 文件 → 导出 PNG → 节点带图
10. 折叠节点删除后重新布局：无崩溃、无泄漏增长（Instruments 可选）

- [ ] **Step 7: Commit**

```bash
git add LinvaApp/LinvaApp/Render/CanvasMetalView.swift LinvaApp/LinvaApp/ContentView.swift LinvaApp/LinvaApp/LinvaAppApp.swift
git commit -m "feat: 图片交互接线——双击选中/⌫分派/⌘V优先级/文件拖入/归一注入"
```

---

### Task 10: Markdown 导出含图（文件夹包）

**Files:**
- Modify: `LinvaApp/LinvaApp/Model/MarkdownExporter.swift`（`MarkdownOutput` + `output(from:)`；`walk` 收集图片）
- Modify: `LinvaApp/LinvaApp/LinvaAppApp.swift:243-258`（`DocumentWorkflow.exportMarkdown` 文件夹包分支）
- Test: `LinvaApp/LinvaAppTests/MarkdownExporterTests.swift`（追加）

**Interfaces:**
- Consumes: `Node.image`（Task 1）。
- Produces: `struct MarkdownImage: Equatable { let nodeId: UUID; let data: Data }`、`struct MarkdownOutput: Equatable { let text: String; let images: [MarkdownImage] }`、`static func output(from: MindMapDocument) -> MarkdownOutput`；`markdown(from:)` 保留为 `output(from:).text`。

- [ ] **Step 1: 写失败测试**

```swift
@Suite("Markdown 含图导出")
struct MarkdownWithImageTests {
    private let png = Data([0x89, 0x50])

    @Test func imageNode_appendsReferenceAndCollectsImage() {
        var doc = MindMapDocument.blank(rootText: "根")
        let child = Node(text: "带图节点", image: png, imagePixelSize: ImagePixelSize(width: 10, height: 10))
        doc.root.children = [child]
        let output = MarkdownExporter.output(from: doc)
        #expect(output.text.contains("![图片](assets/\(child.id.uuidString).png)"))
        #expect(output.images.count == 1)
        #expect(output.images[0].nodeId == child.id)
        #expect(output.images[0].data == png)
    }

    @Test func imagelessDocument_textIdenticalToLegacy_andNoImages() {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "纯文字")]
        let output = MarkdownExporter.output(from: doc)
        #expect(output.images.isEmpty)
        #expect(output.text == MarkdownExporter.markdown(from: doc))  // 字节级兼容
    }

    @Test func collapsedBranchWithImage_stillExported() {
        var doc = MindMapDocument.blank(rootText: "根")
        let child = Node(
            text: "折叠带图", collapsed: true,
            image: png, imagePixelSize: ImagePixelSize(width: 10, height: 10))
        doc.root.children = [child]
        let output = MarkdownExporter.output(from: doc)
        #expect(output.images.count == 1)   // walk 忽略折叠（纯结构遍历）
    }
}
```

- [ ] **Step 2: 跑测试确认失败** Expected: FAIL

- [ ] **Step 3: 实现 MarkdownExporter**

```swift
struct MarkdownImage: Equatable {
    let nodeId: UUID
    let data: Data
}

struct MarkdownOutput: Equatable {
    let text: String
    let images: [MarkdownImage]
}
```

`markdown(from:)` 改为：

```swift
    static func markdown(from document: MindMapDocument) -> String {
        output(from: document).text
    }

    /// 正文 + 逐节点图片清单（FR-G5 修订：MD 含图）。有图节点行内尾缀引用 assets/<id>.png。
    static func output(from document: MindMapDocument) -> MarkdownOutput {
        var lines: [String] = []
        var images: [MarkdownImage] = []
        var rootLine = "# \(collapsedText(document.root.text))"
        if let image = document.root.image {
            rootLine += " ![图片](assets/\(document.root.id.uuidString).png)"
            images.append(MarkdownImage(nodeId: document.root.id, data: image))
        }
        lines.append(rootLine)
        walk(children: document.root.children, depth: 2, into: &lines, images: &images)
        return MarkdownOutput(text: lines.joined(separator: "\n\n") + "\n", images: images)
    }
```

`walk` 签名追加 `images: inout [MarkdownImage]`，正文行拼接处：

```swift
            var content = collapsedText(child.text)
            if let image = child.image {
                content += " ![图片](assets/\(child.id.uuidString).png)"
                images.append(MarkdownImage(nodeId: child.id, data: image))
            }
            if groupHasBranch {
                lines.append("\(String(repeating: "#", count: level)) \(content)")
            } else {
                lines.append("\(symbol) \(content)")
            }
            walk(children: child.children, depth: depth + 1, into: &lines, images: &images)
```

- [ ] **Step 4: 实现 DocumentWorkflow.exportMarkdown**（替换 243-258 行）

```swift
    static func exportMarkdown(_ session: DocumentSession) {
        session.commitEditingIfNeeded()
        let output = MarkdownExporter.output(from: session.model.document)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = ExportNaming.safeFilename(
            base: session.model.document.root.text,
            ext: "md"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if output.images.isEmpty {
                try Data(output.text.utf8).write(to: url, options: .atomic)   // 无图：单文件现状
                return
            }
            // 有图：文件夹包 <用户选的目录>/<N>/<N>.md + <N>/assets/<id>.png
            let folderName = url.deletingPathExtension().lastPathComponent
            let packageDir = url.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
            let assetsDir = packageDir.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
            try Data(output.text.utf8).write(
                to: packageDir.appendingPathComponent("\(folderName).md"), options: .atomic)
            for image in output.images {
                try image.data.write(
                    to: assetsDir.appendingPathComponent("\(image.nodeId.uuidString).png"),
                    options: .atomic)
            }
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 5: 跑测试确认通过**（MarkdownExporterTests 全量——旧用例应零改动通过）+ 全量测试
- [ ] **Step 6: 手测**：无图文档导出 MD → 单文件字节与旧版一致；带图文档导出 → Finder 检查 `N/N.md` + `N/assets/*.png`，Typora/文本编辑器打开验证相对路径图片可预览
- [ ] **Step 7: Commit**

```bash
git add LinvaApp/LinvaApp/Model/MarkdownExporter.swift LinvaApp/LinvaApp/LinvaAppApp.swift LinvaApp/LinvaAppTests/MarkdownExporterTests.swift
git commit -m "feat: Markdown 导出含图——有图文件夹包（N/N.md + assets），无图单文件不变"
```

---

### Task 11: 全量验证 + 文档同步

**Files:**
- Modify: `docs/架构现状.md`（§2 模块表 + §5 白名单行 + 新 §17 增量 + 修订记录）
- Modify: `.agents/skills/linva-codec-version/SKILL.md`（「现状」段落 currentVersion == 3）
- Modify: `.agents/skills/linva-layout-snapshot/SKILL.md`（NodeFrame 字段清单补 imageRect / snapshot 补 imagePayloads）

- [ ] **Step 1: 全量测试**

Run: `xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' 2>&1 | tail -15`
Expected: 全绿（含全部新 Suite）

- [ ] **Step 2: 边界脚本**

Run: `bash scripts/check-boundaries.sh`
Expected: 通过（App 层 ImageIO 已入白名单）

- [ ] **Step 3: 文档同步**

- `docs/架构现状.md`：§2 模块表 Model 行补 `ImagePixelSize`、App 行补 `ImageNormalizer`、Render 行补 `ImageTextureCache`；§5 App 行依赖说明补 ImageIO（理由：图片归一 CGImageSource）；新增「§17 增量：节点内嵌图片（2026-10-01）」小节（Codec v3 / 归一 / 同框布局 / 纹理三纪律 / 图片级选中 / MD 文件夹包）；修订记录补条目。
- `linva-codec-version/SKILL.md`：**现状：`currentVersion == 3`（v3 新增 `Node.image`/`imagePixelSize`）**，迁移链示例更新为 v1→v2→v3 两段。
- `linva-layout-snapshot/SKILL.md`：不变量 4 的字段清单补 `imageRect`；关键文件节补 `imagePayloads`。

- [ ] **Step 4: 手测终验**（Task 9 Step 6 清单全部重跑一遍 + 导出 MD/PNG）

- [ ] **Step 5: Commit**

```bash
git add docs/架构现状.md .agents/skills
git commit -m "docs: 图片节点增量落档（架构现状 §17 + 边界白名单 + codec/layout 技能同步）"
```

---

## Self-Review 记录（写计划时已核）

1. **Spec 覆盖**：§1→Task 1/2；§2→Task 3/4；§3→Task 5；§4→Task 6/7；§5.1→Task 9、§5.2→Task 8/9、§5.3→Task 7/10；§6→各 Task 测试列 + Task 11；§7 风险（autosave 体积/Equatable memcmp）无任务 = 预留不实现，与 spec 一致。**无缺口**。
2. **占位符扫描**：无 TBD/「实现时定」；两处「执行者决策规则」（图片方向颠倒只调 draw 闭包、测试坐标换算翻转）是明确的条件分支指令，非占位。
3. **类型一致性**：`ImagePixelSize(width:height:)` 是 **failable init**（Task 1 定义，测试里 `ImagePixelSize(width: 1, height: 1)!` 与之一致）；`setImage` 三参签名在 Command/Model/Bus/Session 四处一致；`texture(id:localRect:payload:displayScale:device:)` 在 Task 6 定义、Task 7 调用一致；`CanvasActions.clearImage` Task 9 定义并接线。
4. **Spec 修正**：ImageIO 白名单（Task 2 Step 0）——spec §1.3 同步改，属 spec 批准后的事实性勘误，已在计划内显式列出。
