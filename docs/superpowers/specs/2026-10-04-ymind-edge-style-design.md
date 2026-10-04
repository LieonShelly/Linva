# YMind 设计文档：Node 连线样式（正交折线 / 曲线 / 大括号 + 可扩展抽象）

- 日期：2026-10-04
- 状态：待批准（设计已呈 chat，待产品本人评审）
- 上游 PRD：[连线样式 PRD](../../prds/prd-ymind-edge-style-2026-10-04/prd.md)（FR-E1…E5）
- 实现细则：[addendum](../../prds/prd-ymind-edge-style-2026-10-04/addendum.md)
- 体验真源：`prototype/edge-style.html`（三样式 + 组括号几何，浏览器/vision 已验证）
- 涉及技能：`ymind-codec-version`（Codec v7）、`ymind-layout-snapshot`（Connector 契约 / Render-Layout 接缝）、`ymind-command`（setEdgeStyle 命令）

> 本文是 PRD + addendum 的实现落地版。PRD 定需求、addendum 定实现细节，本文记录评审拍板的设计决策与最终接缝，供 writing-plans 与实现引用。
> **扩展性目标**：后续不断加连线样式，加一个样式 = 单一扩展点（enum case + 一个 Provider 文件），引擎/渲染零改动。

---

## 1. 决策记录（评审拍板）

| # | 决策 | 结论 |
|---|------|------|
| D1 | curve/elbow 几何 | **按边构建**：`elbow` 正交折线（现状）；`curve` 三次贝塞尔**水平切向 S 曲线**（对齐 XMind「直出后缓弯」）。 |
| D2 | brace 的本质 | **父-组级连接器**（非每边样式）：每有子的父一个 `}`，父→括号中点（嘴），括号包整组子，子不连边。 |
| D3 | brace 排布 | **brace 强制逻辑树排布**：`edgeStyle == .brace` 时按逻辑树（父左子右竖排）排布 + 产组括号（产品本人拍板）。 |
| D4 | Codec 版本 | `currentVersion` **6 → 7**（layout 已 v5 合入，main=v6）。`edgeStyle` 缺省 `.elbow`，decodeIfPresent 零拒绝。 |
| D5 | 命令 | `setEdgeStyle` 完全镜像 `setLayout`：`MindMapModel.setEdgeStyle(_:) -> EdgeStyle?` → CommandBus Entry undo/redo → Session `commitEditingIfNeeded` → execute。 |
| D6 | **统一 Connector 契约** | 所有样式产统一的 `[ConnectorGeometry]`（`id + path + marker?`），取代 `EdgeGeometry` / `BraceGeometry` 两套。`LayoutSnapshot` 用 `connectors: [ConnectorGeometry]`。Renderer 只描边 Connector + 画 marker，对样式零感知。 |
| D7 | **EdgeStyleProvider 抽象** | 每种样式 = 一个 `EdgeStyleProvider`（protocol）：`requiresLogicArrangement` + `connectors(...)`。`EdgeStyle: String enum` 保持持久化 token（`CaseIterable` 供 UI）。registry 把 case → Provider。**加样式 = enum case + 新建 Provider 文件**。 |
| D8 | 相机 fit | 样式切换触发「有效布局」变化时 `fitVersion += 1`（仿布局 D1）：`edgeStyle` 改且 `requiresLogicArrangement` 使排布改变时再适配。 |

沿用 PRD/addendum 已定假设：作用域全局一种；样式持久化 + 入命令栈。

---

## 2. 目标与非目标

- **目标**：父-子连线支持 正交折线/曲线/大括号 三样式，全局一键切换、即时重绘、无损、随 `.ymind` 持久化、⌘Z 可撤销；PNG 按当前样式导出；**样式可扩展（加一个 = 单一扩展点）**。
- **非目标**：按分支/按节点设样式；连线动画/箭头端头/粗细/颜色（但 `marker` 契约为未来留位）；联系线 Relationship；多结构混用。

---

## 3. 架构与接缝（D6/D7）

分层不变：`Model 变更 → Session.relayout() → LayoutPipeline → LayoutSnapshot → Render`。

- **`EdgeStyle` 枚举**（`Model/MindMapDocument.swift`，与 `LayoutKind` 同文件）——持久化 token：
  ```swift
  enum EdgeStyle: String, Codable, CaseIterable, Sendable, Hashable {
      case elbow, curve, brace          // + 未来：case straight, rounded, …
  }
  ```
  `MindMapDocument.edgeStyle: EdgeStyle = .elbow`；CodingKeys 加 `edgeStyle`；decode `decodeIfPresent ?? .elbow`。
- **`ConnectorGeometry`**（`Layout/LayoutSnapshot.swift`）——统一输出契约：
  ```swift
  struct ConnectorMarker: Equatable {   // 可选标记（brace 嘴旁圆圈；未来箭头/端头）
      enum Kind: Equatable { case circle }
      let kind: Kind
      let center: CGPoint
      let radius: CGFloat
  }
  struct ConnectorGeometry: Equatable {
      let id: UUID                       // 父(组)节点 id
      let path: [CGPoint]                // 折线（曲线/括号先采样）
      let marker: ConnectorMarker?
  }
  ```
  `LayoutSnapshot` 用 `connectors: [ConnectorGeometry]`（缺省 `[]`）取代 `edges` + `braces`。
- **`EdgeStyleProvider`**（`Layout/EdgeStyleProvider.swift`）——扩展点：
  ```swift
  protocol EdgeStyleProvider {
      var requiresLogicArrangement: Bool { get }   // brace=true；elbow/curve=false
      func connectors(
          document: MindMapDocument,
          frames: [UUID: NodeFrame],
          root: Node,
          measure: TextMeasure
      ) -> [ConnectorGeometry]
  }
  ```
  - per-edge 样式（elbow/curve）：遍历父子对，每对产一个 Connector（含父 stem 或直接路径）。
  - 组样式（brace）：每有子父节点产一个 `}` Connector + marker（嘴旁圆圈）。
  - `LayoutSupport` 提供共享几何基元（elbow 折线、curve 采样、brace 公式），Provider 组合它们。
- **registry**（`Layout/EdgeStyleRegistry.swift`）：
  ```swift
  enum EdgeStyleRegistry {
      static func provider(for style: EdgeStyle) -> EdgeStyleProvider
  }
  ```
  `EdgeStyle` 是闭枚举（Codable 兼容），新增样式 = 加 case + 注册 Provider；`switch` 仅存在于 registry 一处。
- **LayoutPipeline**：按 `document.edgeStyle` 取 Provider；`provider.requiresLogicArrangement` 决定有效排布：
  ```swift
  let arrangement: LayoutKind = provider.requiresLogicArrangement ? .logic : document.layout
  // 产 frames（RadialLayout / LogicLayout 排布），随后 provider.connectors(...) 产 Connector
  ```
  曲线/折线不改变排布（沿用 document.layout）；brace 强制逻辑树（D3）。
- **Render**：`MetalRenderer.connectorVertices(snapshot:visibleIds:camera:)`——按 `ConnectorGeometry.path` 逐段描边 + 按 `marker` 画圆圈。替换 `edgeVertices`/`braceVertices`。

---

## 4. 样式几何

### 4.1 elbow / curve（per-edge，D1）

共享基元 `LayoutSupport.edgePoints(from:to:style:) -> [CGPoint]`：
- `elbow`：3/4 段正交折线。
- `curve`：三次贝塞尔水平切向 S 曲线采样（`segments=20`）：
  - `dir = sign(end.x − start.x)`（|dx|≥|dy|）；`k = clamp(|dx|·0.4, 18, 56)`。
  - 控制点 `c1 = (start.x + dir·k, start.y)`、`c2 = (end.x − dir·k, end.y)`。
  - 垂直主导边（|dy|>|dx|）用垂直切向。
- 每个父-子对产一个 `ConnectorGeometry`（`path = edgePoints`，无 marker）。

### 4.2 brace（组连接器，D2/D3）

`BraceProvider.connectors(...)` 对每个有子父节点产一个 Connector，几何按参考 HTML 公式（产品本人逐字 HTML `brace-xmind.html`）：
```
yTop    = 首子 center.y；yBottom = 末子 center.y
if N == 1: span = max(子高·0.85, 28); yTop = cy−span/2; yBottom = cy+span/2
yMid = (yTop + yBottom) / 2            // = 父 center.y（父=首末子中点，原型已修）
w = 括号宽（主 56 / 子 34，按层级）
xTip = mouthX + (hasCircle ? 15 : 10)；xStem = mouthX + w·0.54；xRight = mouthX + w − 8
r = min(16, (yBottom−yTop)/4, xRight−xStem, xStem−xTip)
top:    M xRight yTop  Q xStem yTop, xStem yTop+r  L xStem yMid−r  Q xStem yMid, xTip yMid
bottom: M xTip yMid    Q xStem yMid, xStem yMid+r  L xStem yBottom−r  Q xStem yBottom, xRight yBottom
```
- 父 → 嘴：短直线 `(父右缘, yMid) → (mouthX, yMid)` 并入 path 首段。
- `hasCircle` → `ConnectorMarker(.circle, center: (xTip−r_c−1, yMid), radius: 4.5)`（折叠标记）。
- 颜色：YMind 单一边色（edge separator），不用参考双色（那是 XMind 主题）。

### 4.3 扩展新样式（D7，单一扩展点）

加一个 per-edge 样式（如 straight / rounded）：
1. `EdgeStyle` 加 `case straight`。
2. 新建 `StraightStyleProvider.swift`：实现 `connectors(...)`（可复用 `LayoutSupport.edgePoints` 基元）+ `requiresLogicArrangement = false`。
3. `EdgeStyleRegistry` 注册。
4. 工具栏 Picker 因 `CaseIterable` 自动出现。
**引擎 / Render / Codec 零改动。** 组样式同理（`requiresLogicArrangement = true` + 组 Connector 逻辑）。

---

## 5. Codec v7（FR-E1）

- `MindMapDocument.currentVersion = 6 → 7`；`YMindCodec.decode` 迁移链末尾 `if doc.version == 6 { doc.version = 7 }`。
- 老文件（≤v6）无 `edgeStyle` → 缺省 `.elbow`，零拒绝。
- `sanitize` 不变（文档级枚举标量）。

---

## 6. setEdgeStyle 命令与会话（FR-E1/E4）

- `MindMapCommand` 增 `case setEdgeStyle(kind: EdgeStyle)`。
- `MindMapModel.setEdgeStyle(_ kind:) -> EdgeStyle?`：相同 nil（no-op）；否则改 `document.edgeStyle` 返旧值。
- `CommandBus.applyForward`：
  ```swift
  case let .setEdgeStyle(kind):
      guard let old = model.setEdgeStyle(kind) else { return nil }
      return Entry(undo: { _ = self.model.setEdgeStyle(old) },
                   redo: { _ = self.model.setEdgeStyle(kind) })
  ```
- `DocumentSession`：
  ```swift
  var edgeStyle: EdgeStyle { model.document.edgeStyle }
  func setEdgeStyle(_ kind: EdgeStyle) { commitEditingIfNeeded(); commandBus.execute(.setEdgeStyle(kind: kind)) }
  ```
- **fit（D8）**：`markDirtyAndRelayout()` 末尾比较「有效排布」（`provider.requiresLogicArrangement` 与 `document.layout` 组合）→ 变化则 `fitVersion += 1`。

---

## 7. 渲染（FR-E3）

- `MetalRenderer.connectorVertices(snapshot:visibleIds:camera:)`：遍历 `snapshot.connectors`，任一端点可见才画；`path` 逐相邻点 `segmentQuad` 描边；`marker` 画圆圈（`circleQuad`）。替换 `edgeVertices`/`braceVertices`。
- 曲线采样在 Provider 侧（`LayoutSupport.edgePoints`），Renderer 只描边。
- 无新 shader。

---

## 8. UI（FR-E4）

- `MainToolbar` 增 `Picker("连线样式", selection: Binding(get:set:))`，`.menu`，`ForEach(EdgeStyle.allCases)`（`CaseIterable` 自动扩展），当前样式高亮；回调 `setEdgeStyle`。
- 切到 brace 时若 `document.layout == .radial`，画布按逻辑树重排（D3）；切换器旁可提示「大括号按总分树显示」。
- 可选快捷键循环（⇧E），不与现有快捷键冲突。

---

## 9. 导出（FR-E5）

- `PNGExporter` **零改动**：`document.edgeStyle` 在文档里，`LayoutPipeline` 按 Provider 产 Connector 快照，`relayout()` 产出哪张渲染哪张。

---

## 10. 测试

| 层 | 用例 |
|----|------|
| Model/Codec | `edgeStyle` 缺省 `.elbow`；v7 往返（elbow/curve/brace）；≤v6 老文件缺省零拒绝；迁移链不破坏 |
| 命令 | `setEdgeStyle` 入栈 / undo / redo；no-op 不入栈；不改选中 |
| Registry | 每个 `EdgeStyle` case 有 Provider；`requiresLogicArrangement`（elbow/curve=false，brace=true） |
| 有效排布 | brace 强制逻辑树 + 组 Connector；elbow/curve 按 document.layout |
| Layout | elbow 折线端点；curve S 曲线控制点（水平/垂直/斜边）；brace Connector（首末子 yTop/yBottom、单子最小跨度、嘴=父中心、xStem/xRight、r、path、marker） |
| Render | `connectorVertices` 描边 + marker 圆圈（真 Metal 冒烟）；无 `edgeVertices`/`braceVertices` 遗留 |
| 交互 | 切换后选中/折叠保持；切 brace 触发 fit；任意选中态可用；⌘Z 往返 |
| 导出 | PNG 按当前样式渲染 |
| 边界 | `check-boundaries.sh` 全绿（无新增 import；几何用 CoreGraphics/Foundation） |

---

## 11. 验证与验收

- 单测全绿；`xcodebuild test`（YMindAppTests）。
- 真机/模拟器冒烟：三样式切换；辐射下切 brace → 逻辑树 + 组括号（对齐 `brace-xmind.html`）；嘴对准父；⌘Z 往返；保存重开保持；PNG 导出样式一致。
- `check-boundaries.sh` 绿；`currentVersion = 7`。

---

## 修订记录

| 日期 | 说明 |
|------|------|
| 2026-10-04 | 初稿：D1–D6（共享构建器、局部系几何、Codec v7、命令、strokePolyline、不做 fit）。 |
| 2026-10-04 | 修订一：brace 定为组连接器 + 强制逻辑树（D2/D3）；几何按产品 HTML；curve 改水平切向 S 曲线；`LayoutSnapshot.braces`；brace 触发 fit。 |
| 2026-10-04 | 修订二（扩展性设计，D6/D7/D8）：统一 `ConnectorGeometry` 契约取代 Edge/Brace 两套；`EdgeStyleProvider` 抽象 + registry；加样式 = enum case + 一个 Provider 文件，引擎/渲染/Codec 零改动。 |
