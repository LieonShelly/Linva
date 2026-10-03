# YMind — Motion Tokens

> 动效规格。**SwiftUI 层**（浮层/菜单/对话框/工具条）与 **Metal 层**（节点增删/选中/边过渡）约束不同，必须分开定义。
> 尊重 macOS「减弱动态效果」（reduced-motion）。
> 与 `design-tokens.md`、`components/*.md`、`prototype/design/*.html` 配套。

---

## 1. 设计原则

1. **丝滑 = 物理，不是匀速**。全部用 spring / cubic-bezier，不用线性。
2. **快进慢出**：进入比退出略快，退出用更柔的曲线。
3. **两层解耦**：Metal 画布动画与 SwiftUI 浮层动画独立驱动、独立时长——**绝不跨层等对方**（不同 runloop/提交时机）。
4. **空间连续**：新增节点从其父级边缘生长；删除向父级收缩。节点之间位移用「布局快照 diff」过渡。
5. **reduced-motion**：开启后节点增删/选中退化为瞬时切换，只保留透明度淡入淡出，关闭位移/缩放。

---

## 2. 时长与曲线 Token（全局）

| Token | 值 | 用途 |
|---|---|---|
| `--m-fast` | 120ms | 悬停、按下、色点激活、焦点环 |
| `--m-base` | 200ms | 工具条状态、搜索计数、面板开关 |
| `--m-slow` | 300ms | 浮层进入/退出、菜单 |
| `--m-spring-snappy` | `spring(response:0.30, dampingFraction:0.72)` | 节点增删/选中（Metal） |
| `--m-spring-gentle` | `spring(response:0.40, dampingFraction:0.82)` | 编辑浮层、搜索浮层 |
| `--m-ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | 一般出现（easeOutQuint） |
| `--m-ease-in-out` | `cubic-bezier(0.65, 0, 0.35, 1)` | 位移过渡 |
| `--m-stagger` | 24ms | 批量节点出现的错峰步进 |
| `--m-max` | 400ms | 单条动画时长上限（保护 120Hz 不糊） |

---

## 3. SwiftUI 层（浮层 / 菜单 / 对话框 / 工具条）

> 实现：SwiftUI `withAnimation` / `.animation(_:value:)` / `.transition`。这些动画作用于壳层，不碰 Metal 快照。

### 3.1 编辑浮层（NodeEditorOverlay）

| 事件 | 动效 | Token |
|---|---|---|
| 出现 | 从节点中心轻微放大 + 淡入 | `--m-spring-gentle` |
| 消失（提交） | 快速淡出 | `--m-fast` |
| 焦点环 | 透明度过渡 | `--m-fast` |

**reduced-motion**：仅淡入，无缩放。

### 3.2 搜索浮层（SearchBar）

| 事件 | 动效 | Token |
|---|---|---|
| 出现 | 顶部滑入 + 淡入 | `--m-spring-gentle` |
| 消失（Esc） | 上滑 + 淡出 | `--m-base` |
| 命中切换 | 画布居中（`centerCamera`）在 Metal 层过渡 | 见 §4 |

### 3.3 工具条（MainToolbar）

| 事件 | 动效 | Token |
|---|---|---|
| 按钮 hover | 背景淡入 | `--m-fast` |
| 按钮按下 | 轻微下压（`translateY(1)`）| `--m-fast` |
| 色点激活 | 环出现 | `--m-fast` |
| 缩放百分比变化 | 数字切换（淡入淡出） | `--m-base` |

> **不做**：工具条整体滑动、图标弹性。Mac 工具条保持克制。

### 3.4 对话框 / 横幅（RecoveryBanner / ImportPreview / NSAlert）

| 事件 | 动效 | Token |
|---|---|---|
| 出现 | 淡入 + 轻微上移 | `--m-slow` / `--m-ease-out` |
| 消失 | 淡出 | `--m-base` |

> NSAlert 由系统驱动，不自定义。

---

## 4. Metal 层（节点增删 / 选中 / 边过渡）

> 实现：Metal 渲染器消费 `LayoutSnapshot` diff。节点增删/选中/边在 Render 层做**补间（interpolation）**，不触发 `CommandBus` 重入，不阻塞布局。
> 关键约束（ymind-layout-snapshot）：**Render 只吃 Snapshot**，动画帧中间态只在 Render 内部合成，不写回 Model/Session。

### 4.1 新增节点（addChild / addSibling / paste / import）

| 阶段 | 动效 | Token |
|---|---|---|
| 1. 父级/邻级轻微让位 | 现有节点位移过渡 | `--m-spring-snappy`（位移用 `--m-ease-in-out`） |
| 2. 新节点生长 | 从父级边缘中心 `scale(0.6→1)` + `opacity(0→1)` | `--m-spring-snappy` |
| 3. 新边绘制 | 边从父锚点「生长」（`strokeEnd` 0→1） | `--m-base` |

**reduced-motion**：第 1 步瞬时，第 2 步仅淡入（无缩放），第 3 步瞬时。

### 4.2 删除节点

| 阶段 | 动效 | Token |
|---|---|---|
| 1. 目标收缩 | 向父级边缘 `scale(1→0.6)` + `opacity(1→0)` | `--m-spring-snappy` |
| 2. 兄弟节点让位 | 位移过渡 | `--m-ease-in-out` |
| 3. 边消失 | `strokeEnd` 1→0 | `--m-fast` |

### 4.3 选中 / 取消选中

| 事件 | 动效 | Token |
|---|---|---|
| 选中 | 泛光环淡入（`--p-accent-soft` 3px 环）| `--m-base` |
| 取消 | 泛光环淡出 | `--m-fast` |
| 框选（marquee） | 矩形随指针实时更新，出现时淡入 | `--m-fast` |

### 4.4 折叠 / 展开（BranchToggle）

| 事件 | 动效 | Token |
|---|---|---|
| 折叠 | 整枝淡出 + 收缩到分叉控件，分叉控件转实心 | `--m-base` |
| 展开 | 整枝淡入 + 生长，分叉控件转白底 | `--m-base` |
| 分叉控件 hover | 轻微放大 `scale(1.08)` | `--m-fast` |

### 4.5 搬枝拖拽 / 放置反馈

| 事件 | 动效 | Token |
|---|---|---|
| 拖起 | 目标 `opacity(0.55)` + 置顶 | `--m-fast` |
| 放置反馈（插入线/镶边/中线引导） | 淡入 | `--m-fast` |
| 放置生效 | 整枝位移过渡 | `--m-ease-in-out` |

### 4.6 相机 / 缩放

| 事件 | 动效 | Token |
|---|---|---|
| 滚轮 / 缩放 | 跟随指针锚点，实时（**不补间**，用户输入要即时） | — |
| 适应画布（fit） | 缩放+平移补间 | `--m-spring-gentle` |
| 搜索命中居中（centerCamera） | 平移补间到目标 | `--m-spring-gentle` |

---

## 5. 性能纪律（120Hz）

1. **只动画 transform / opacity / strokeEnd**——这些 GPU 友好。**禁止**动画 width/height/color 走 CoreAnimation 隐式（易造成 layout thrash / 主线程掉帧）。
2. 节点增删过渡的中间态**在 Render 内做顶点插值**，不逐帧重算 `LayoutSnapshot`。
3. 批量操作（导入、粘贴整枝、展开大枝）用 **stagger（`--m-stagger` 24ms）**，避免一帧内全部启动。
4. `CADisplayLink` / Metal 提交循环**独立于 SwiftUI**，浮层动画不阻塞画布帧。
5. 每条动画有硬性时长上限 `--m-max`(400ms)，防止 spring 衰减拖尾卡在中间态。

---

## 6. reduced-motion 落地清单

| 位置 | 关闭后行为 |
|---|---|
| Metal 节点增删 | 瞬时切换 + 仅淡入淡出（无缩放/位移） |
| Metal 边绘制 | 瞬时 |
| SwiftUI 编辑浮层 | 仅淡入 |
| SwiftUI 搜索浮层 | 仅淡入 |
| 相机 fit / 居中 | 瞬时跳转 |

> 实现检测：SwiftUI `@Environment(\.accessibilityReduceMotion)`；Metal 层从 AppKit `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`（或经环境传递）。
