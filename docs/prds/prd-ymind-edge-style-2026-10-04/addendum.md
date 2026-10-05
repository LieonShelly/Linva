# Addendum：Node 连线样式 — 实现侧细节（不进 PRD 主线）

**所属 PRD：** `docs/prds/prd-ymind-edge-style-2026-10-04/prd.md`
**实现设计（先读）：** `docs/superpowers/specs/2026-10-04-ymind-edge-style-design.md`（D1–D8 决策，本文件是其实现细则）
**日期：** 2026-10-04
**读者：** 开发 Agent / 方案设计（specs → plans）；先读 PRD §4 FR-E1…E5、spec D1–D8、§6 验收要点。

> 涉及技能：`ymind-codec-version`（Codec v7）、`ymind-layout-snapshot`（Connector 契约 / Render-Layout 接缝）、`ymind-command`（setEdgeStyle 命令）。开发前读对应 skill。
> **扩展性铁律**：加新样式只允许动 `EdgeStyle` 枚举 + 新建 Provider 文件 + registry 注册 +（per-edge 样式）`LayoutSupport.edgePoints` 一个 case，**不得改引擎/Render/Codec**（spec D7）。

---

## 1. 统一 Connector 契约（spec D6，FR-E2/E3 细则）

- **`ConnectorGeometry`**（`Layout/LayoutSnapshot.swift`）取代 `EdgeGeometry` + `BraceGeometry` 两套：
  ```swift
  struct ConnectorMarker: Equatable {
      enum Kind: Equatable { case circle }
      let kind: Kind
      let center: CGPoint
      let radius: CGFloat
  }
  struct ConnectorGeometry: Equatable {
      let id: UUID
      let path: [CGPoint]
      let marker: ConnectorMarker?
  }
  ```
- **`LayoutSnapshot`** 用 `connectors: [ConnectorGeometry]`（缺省 `[]`），删 `edges`/`braces` 字段。现有 `EdgeGeometry` 类型删除（或迁移为内部别名），`MetalRenderer.edgeVertices`/`braceVertices` 合并为 `connectorVertices`。
- **`EdgeStyleProvider`**（`Layout/EdgeStyleProvider.swift`）：
  ```swift
  protocol EdgeStyleProvider {
      var requiresLogicArrangement: Bool { get }
      func connectors(document: MindMapDocument, frames: [UUID: NodeFrame],
                      root: Node, measure: TextMeasure) -> [ConnectorGeometry]
  }
  ```
- **`EdgeStyleRegistry`**（`Layout/EdgeStyleRegistry.swift`）：`provider(for:)` 是唯一 `switch edgeStyle` 处。默认 Provider 列表：`ElbowProvider`、`CurveProvider`、`BraceProvider`（各一个文件）。
- **`LayoutSupport` 共享几何基元**（`Layout/LayoutSupport.swift` 增）：
  ```swift
  static func edgePoints(from: CGPoint, to: CGPoint, style: EdgeStyle) -> [CGPoint]
  static func sampleCubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, segments: Int) -> [CGPoint]
  ```
  - `elbow`：3 段正交折线。
  - `curve`：水平切向 S 曲线（`k = clamp(|dx|·0.4, 18, 56)`，垂直主导边用垂直切向）采样 20 段。
  - brace 的 `}` 公式见 spec §4.2（独立实现，不借 edgePoints）。

## 2. LayoutPipeline 分派（spec D3/D7）

```swift
func relayout(document: MindMapDocument) -> LayoutSnapshot {
    let provider = EdgeStyleRegistry.provider(for: document.edgeStyle)
    let arrangement: LayoutKind = provider.requiresLogicArrangement ? .logic : document.layout
    let frames: [UUID: NodeFrame]
    switch arrangement {
    case .radial: frames = RadialLayout.placeFrames(document: document, measure: measure)
    case .logic:  frames = LogicLayout.placeFrames(document: document, measure: measure)
    }
    let connectors = provider.connectors(document: document, frames: frames, root: document.root, measure: measure)
    // branchToggles / imagePayloads 照旧收集
    return LayoutSnapshot(frames: frames, connectors: connectors, …)
}
```
- 排布引擎瘦身为「只产 frames」；Connector 由 Provider 产（样式解耦）。
- `RadialLayout` / `LogicLayout` 的现有 `layout()` 拆出 `placeFrames`；测试对应改。

## 3. brace 强制逻辑树 + 组 Connector（spec D2/D3）

- `BraceProvider.connectors(...)`：对有子的父节点递归产 Connector。父 = 首末子中心中点（原型已验证，嘴对准父）。
- 几何按参考 HTML 公式（`brace-xmind.html`，spec §4.2）：`xTip/xStem/xRight`、`Q/L` 路径、`r = min(16, 跨度/4, xRight−xStem, xStem−xTip)`、单子最小跨度 `max(子高·0.85, 28)`、`hasCircle → ConnectorMarker(.circle)`。
- 颜色：YMind 单一边色（edge separator），不用双色。
- 折叠标记（嘴旁圆圈）关联：`hasCircle` 暂定 = 该父有折叠后代或根选中态（实现时定，先恒 false 或根 true，见 PRD §9 开放问题）。

## 4. Codec v7（FR-E1）

- `MindMapDocument.currentVersion = 6 → 7`；`YMindCodec.decode` 迁移链末尾 `if doc.version == 6 { doc.version = 7 }`。
- `edgeStyle` 字段 decodeIfPresent 缺省 `.elbow` 零拒绝；`sanitize` 不变。

## 5. setEdgeStyle 命令与会话（FR-E1/E4）

- `MindMapCommand.setEdgeStyle(kind:)`；`MindMapModel.setEdgeStyle(_:) -> EdgeStyle?`；`CommandBus` Entry undo/redo；`DocumentSession.setEdgeStyle(_:)` = `commitEditingIfNeeded()` → execute。
- **fit（D8）**：`markDirtyAndRelayout()` 比较有效排布（`provider.requiresLogicArrangement ? .logic : document.layout`）变化 → `fitVersion += 1`。

## 6. 渲染（FR-E3）

- `MetalRenderer.connectorVertices(snapshot:visibleIds:camera:)`：`snapshot.connectors` 逐条 `path` 相邻点 `segmentQuad`；`marker` 画圆圈。替换 `edgeVertices`/`braceVertices`。
- 无新 shader；曲线采样在 Provider 侧。

## 7. UI（FR-E4）

- `MainToolbar`：`Picker("连线样式")` `.menu` + `ForEach(EdgeStyle.allCases)`；回调 `setEdgeStyle`。`EdgeStyle` 须 `CaseIterable`。
- 快捷键 ⇧E 循环（不与现有冲突，实现时确认）。

## 8. 导出（FR-E5）

- `PNGExporter` 零改动：走 `LayoutPipeline` 快照（含 connectors）。

## 9. 测试建议

- **Codec**：v7 往返三样式；≤v6 兜底；迁移链不破坏。
- **Registry**：每 case 有 Provider；`requiresLogicArrangement`（elbow/curve=false，brace=true）。
- **有效排布**：brace 强制逻辑树；elbow/curve 按 document.layout。
- **Layout**：elbow 折线端点；curve S 曲线控制点（水平/垂直/斜边）；brace Connector（首末子 yTop/yBottom、单子跨度、嘴=父中心、xStem/xRight、r、path、marker）。
- **Render**：`connectorVertices` 描边 + marker 圆圈（真 Metal 冒烟）；无 edgeVertices/braceVertices 遗留。
- **交互**：切换后选中/折叠保持；切 brace 触发 fit；⌘Z 往返；任意选中态可用。
- **导出**：PNG 按当前样式（真 Metal）。
- **扩展演练（重要）**：加一个最小 per-edge 样式（如 straight）验证「只动 enum + Provider + registry」即可生效——作为 D7 的回归测试。

## 10. 分层/边界清单

| 关注点 | 处理 |
|--------|------|
| Model / Codec | `MindMapDocument.edgeStyle` + v7；引擎/Render 不读 Model 树 |
| Layout | `placeFrames`（排布）+ `EdgeStyleProvider.connectors`（几何）；`LayoutSnapshot.connectors` 统一契约 |
| Render | `connectorVertices` 合并描边 + marker；无新 shader |
| 扩展 | 加样式 = enum case + Provider 文件 + registry 注册 +（per-edge）`edgePoints` case；UI 默认显式三选一，需暴露时改 `ForEach(EdgeStyle.allCases)` |
| `check-boundaries.sh` | 不新增 import；几何用 CoreGraphics/Foundation，白名单覆盖 |
| 与 1.0 并行 | 接缝 = `LayoutSnapshot.connectors` + Codec v7 独占 |
