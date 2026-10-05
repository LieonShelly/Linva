# Linva Motion Tokens

> 状态：正式 UI/UX 设计基线（2026-10-02）。定义 Linva 的动效 token：时长、缓动、spring、stagger。**硬性拆分 SwiftUI 层（浮层/菜单/对话框/工具条）与 Metal 层（节点增删/选中/边过渡/折叠）**——实现层不同，约束不同，动效必须分层设计（linva-design 硬约束）。
>
> 顶层原则：**丝滑 = 尊重系统节奏 + 一致的运动语言 + reduced-motion 降级**。所有动效服务于「空间连续性」与「因果反馈」，不为炫技。

---

## 0. 双分层

| 层 | 技术 | 消费方 | 负责的动效 |
|----|------|--------|-----------|
| **SwiftUI / AppKit 壳** | SwiftUI `withAnimation` / `Animation` / `.animation(_:value:)` / 过渡；AppKit `NSTextView` | 工具条、编辑浮层、搜索条、导入预览、恢复横幅、菜单、对话框、工具条溢出菜单 | 浮层出现/消失、聚焦、hover 反馈、计数变化、菜单 |
| **Metal 画布** | `MetalRenderer` 顶点缓冲每帧插值；`CASpringAnimation`/`CADisplayLink` 驱动（若用 layer 化） | `CanvasMetalView` / `MetalRenderer.encodeContent` | 节点增删/移动/选中、边过渡、折叠展开、纸面/网格、拖放反馈、框选 |

> 分界：**浮在上层的 UI**（编辑浮层、搜索条、横幅）归 SwiftUI；**画布上画的内容**（节点、边、折叠钮、选中光环、拖放线、框选框）归 Metal。二者互不跨层动效。

---

## 1. 动效 token（统一语义）

### 1.1 时长 token

| token | 值 | 语义 |
|-------|-----|------|
| `motion.duration.instant` | 0ms | 状态切换无过渡（禁用态、纯逻辑） |
| `motion.duration.fast` | 120ms | hover 反馈、按压、微交互 |
| `motion.duration.base` | 200ms | 选中光环、边框、计数 |
| `motion.duration.medium` | 280ms | 节点出现/折叠、边过渡、浮层出现 |
| `motion.duration.slow` | 320ms | 大规模布局重排、纸面氛围 |
| `motion.duration.entrance` | 400ms | 首屏/搜索命中「揭示」动画（可轻微交错） |

### 1.2 缓动 token

| token | 定义 | 用途 |
|-------|------|------|
| `motion.easing.out` | `cubic-bezier(0.22, 1, 0.36, 1)` | **默认出场**：快起缓停，元素进入场景（节点、浮层） |
| `motion.easing.inOut` | `cubic-bezier(0.42, 0, 0.58, 1)` | 状态过渡（选中、边框、计数） |
| `motion.easing.standard` | SwiftUI `.easeOut`（iOS 17+ 语义缓动） | 浮层/菜单等系统控件 |
| `motion.easing.linear` | linear | 只在极短、感知为「同步」的位移（禁 hover 曲线） |

> 对应 SwiftUI：`Animation.easeOut(duration:)` 或 `Animation.timingCurve(0.22, 1, 0.36, 1, duration:)`。`.easeInOut` 用于双向状态。Metal 层用同一 `cubic-bezier` 采样逐帧插值。

### 1.3 spring token（SwiftUI 壳，浮层/编辑浮层）

| token | 值 | 用途 |
|-------|-----|------|
| `motion.spring.soft` | `response 0.35, dampingFraction 0.86` | 浮层/编辑浮层轻微弹性入场 |
| `motion.spring.snappy` | `response 0.2, dampingFraction 0.9` | 计数、小状态 |
| `motion.spring.heavy` | `response 0.5, dampingFraction 0.8` | 拖放/搬枝吸附感（画布用 Metal，见下） |

> 现状 `MetalRenderer`/原型用 `cubic-bezier(0.22,1,0.36,1)` 即可；不强制 spring。**避免过阻尼/欠阻尼过度**——HIG 要求克制。

### 1.4 stagger token

| token | 值 | 用途 |
|-------|-----|------|
| `motion.stagger.entrance` | 28ms | 首屏整树节点逐枝入场（可作氛围，非必须） |
| `motion.stagger.search` | 20ms | 搜索命中逐个「点亮」（非必须，克制） |

> stagger 一律**可选**；reduced-motion 下全部关闭。

---

## 2. Metal 层动效规格（画布内容）

> 实现提示：`MetalRenderer.encodeContent` 每帧重绘，动效 = 在 **Snapshot 之间做顶点插值**。当前架构「Layout 产 Snapshot → Render 消费」已支持每帧重算；建议在 Render 维护「当前/目标」两套顶点，`draw(in:)` 用 `motion.duration.medium` + `motion.easing.out` 插值。详见 `components/canvas.md` 与 `linva-layout-snapshot`。

### 2.1 节点出现（新增节点）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.medium` (280ms) + `motion.easing.out` |
| 表现 | 从父节点方向 `scale 0.86 → 1` + `opacity 0 → 1` 入场（对齐原型 `node-in`） |
| reduced-motion | 直接落位，无 scale（仅可选极短 opacity 或省略） |

### 2.2 节点删除

| 属性 | 值 |
|------|-----|
| token | `motion.duration.fast` (120ms) + `motion.easing.out` |
| 表现 | 目标 `opacity → 0` + `scale → 0.92` 后移除；**父枝其余节点平滑聚合**（布局重排过渡 280ms） |
| 注意 | 删除走命令栈，撤销恢复时反向播放入场 |

### 2.3 选中 / 反选（光环）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.base` (200ms) + `motion.easing.inOut` |
| 表现 | 选中光环 `sem.color.accent.soft` 3pt 淡入；反选淡出 |
| reduced-motion | 直接切换（或极短淡入） |

### 2.4 边过渡（连线重排）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.medium` (280ms) + `motion.easing.inOut` |
| 表现 | 边控制点随布局插值平滑移动（搬枝/折叠/新增子节点时） |
| 注意 | 边走 `EdgeGeometry.points`，逐点插值即可；勿瞬时跳变 |

### 2.5 折叠 / 展开（+ 折叠钮 + 子树）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.medium` (280ms) + `motion.easing.out` |
| 表现 | 子树节点聚合/散开，边同步过渡 |
| 折叠钮 | **仅折叠态显示**（展开入口 `+N`）：折叠时 `motion.duration.fast` 出现；点击 `scale 0.96` 按压反馈 |
| 节点点击折叠 | 展开节点点击本体 → 折叠（子树聚合）；折叠节点点击本体或 `+N` 钮 → 展开 |

### 2.6 拖放反馈（搬枝 / 插入线 / 改侧带）

| 属性 | 值 |
|------|-----|
| token | 插入线 `motion.duration.fast` 淡入；放置意图（成子/插前/插后/改侧）即时高亮 |
| 表现 | 节点 drop-target 光环 + 插入线 + 根镶边随 `DropIntent` 即时切换（不拖尾） |
| 注意 | 拖放反馈应**即时**，不引入延迟；高亮层叠在选中之上 |

### 2.7 框选矩形（marquee）

| 属性 | 值 |
|------|-----|
| token | 无动画（跟随指针，实时绘制） |
| 表现 | 跟随光标绘制 `sem.color.accent` 1.5pt 描边 + 淡底；释放后命中节点逐个补选中光环 |

### 2.8 纸面 / 点阵（可选氛围）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.slow` (320ms) 淡入 |
| 表现 | 画布纸感底与极淡点阵在窗口出现/缩放下保持静止（不随缩放滚动，静态贴画布） |
| 注意 | 网格若随相机缩放则无需动画；仅首屏淡入即可 |

---

## 3. SwiftUI 层动效规格（浮层/菜单/对话框/工具条）

> 实现提示：全部走 SwiftUI 声明式动画。浮层用 `.transition` + `withAnimation`；计数/状态用 `.animation(_:value:)`。**必须带 `value` 参数**（swiftui-expert-skill 硬规则）。

### 3.1 编辑浮层（NodeEditorOverlay）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.medium` + `motion.spring.soft` |
| 表现 | 从节点原位放大出现（`scale 0.92 → 1` + 轻微淡入），带 `.tint` 2pt 描边；Esc/提交时同速缩回 |
| 焦点 | 出现即 `makeFirstResponder`，光标置于文末（现状已有） |

### 3.2 搜索条（SearchBar）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.fast` (120ms) 滑入/淡入（自顶下，对齐工具条下方） |
| 表现 | 出现时文本域获焦；关闭 Esc 反向滑出 |
| 计数 | `monospacedDigit` 数字变化用 `.animation(.snappy, value:)` 轻微过渡（可省略） |

### 3.3 恢复横幅（RecoveryBanner）

| 属性 | 值 |
|------|-----|
| token | `motion.duration.medium` 自上滑入（对齐搜索条） |
| 表现 | 常驻顶部直到用户处理；两按钮 `borderedProminent`/默认 |

### 3.4 导入预览（ImportPreviewView）

| 属性 | 值 |
|------|-----|
| token | 系统 sheet/浮层过渡（`motion.easing.standard`） |
| 表现 | 确认/取消按钮 Esc 可用；确认后树入场 |

### 3.5 工具条按钮 / 色点

| 属性 | 值 |
|------|-----|
| token | `motion.duration.fast` (120ms) + `motion.easing.out` |
| 表现 | hover 淡变底、按压 `translateY(1px)`（对齐原型）；色点 hover `scale 1.08`、激活光环 `motion.duration.base` |
| 溢出菜单 | 系统 `ToolbarOverflowMenu`，无需自定义动效 |

### 3.6 计数 / 状态文本

| 属性 | 值 |
|------|-----|
| token | `motion.duration.fast` (120ms) |
| 表现 | 选中计数、缩放 % 变化用 `.animation(_, value:)`；**不做数字滚动**（克制） |

---

## 4. Reduced Motion 降级（无障碍硬约束）

> 尊重 `@Environment(\.accessibilityReduceMotion)`（SwiftUI）与 Metal 层读 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`。

| 开关 | 全局行为 |
|------|---------|
| `accessibilityReduceMotion` = true | 关闭所有 scale/translate/opacity 过渡：节点直接落位、选中直接切换、浮层无 spring、stagger 全关、纸面不淡入 |
| 允许保留 | 仅纯 alpha ≤ 60ms 的最短淡入（可选）——**建议完全关闭以彻底丝滑** |

**实现建议**（对齐 HIG 11.3 / swiftui-expert-skill）：
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion
// SwiftUI
.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isSelected)
// Metal：Renderer 收到 reduceMotion 后跳过插值，直接落位
```

---

## 5. 分界线速查（实现时别越层）

| 动效 | 归属 |
|------|------|
| 节点增删/移动/选中/边/折叠/拖放线/框选/纸面 | **Metal** |
| 编辑浮层/搜索条/恢复横幅/导入预览/工具条/菜单/计数 | **SwiftUI** |
| 文字编辑浮层的 caret | SwiftUI（`NSTextView` 自带） |
| 折叠钮 hover/按压反馈 | **Metal**（画布上） |

---

## 6. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-10-02 | 首版：SwiftUI / Metal 双分层动效 token，时长/缓动/spring/stagger，reduced-motion 降级 |
