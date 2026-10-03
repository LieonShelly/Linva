# YMind — Component Spec: Menu Bar（菜单栏）

> macOS 强制（HIG Rule 1.1）：App/File/Edit/View/Window/Help。现状 `YMindAppApp.DocumentCommands` 已含部分。
> **目标**：核对补齐 HIG 标准菜单，所有动作有快捷键，动态使能。

---

## 1. 标准菜单结构

| 菜单 | 必需项 | 现状 | 待补 |
|---|---|---|---|
| **App（应用名）** | About / Settings ⌘, / Services / Hide ⌘H / Hide Others / Show All / Quit ⌘Q | SwiftUI 自动生成 | 核对 |
| **File** | 新建 ⌘N / 打开… ⌘O / 关闭 ⌘W / 保存 ⌘S / 另存为 ⇧⌘S / 导入 ▸ | ✅ 已含（`DocumentCommands`） | 补齐 ⌘W 关窗 |
| **Edit** | 撤销 ⌘Z / 重做 ⇧⌘Z / 剪切 ⌘X / 复制 ⌘C / 粘贴 ⌘V / 全选 ⌘A / 查找 ▸ | ✅ 撤销重做/搜索/改侧 | 剪切复制粘贴、⌘A 全选、查找 ⌘F |
| **View** | 适应画布 / 放大 ⌘+ / 缩小 ⌘− / 实际大小 ⌘0 / 切换工具条 | 部分 | 工具条切换、缩放快捷键 |
| **Window** | 最小化 ⌘M / 缩放 / 前置全部 | SwiftUI 自动 | 核对 |
| **Help** | 帮助 | SwiftUI 自动 | 核对 |

---

## 2. 快捷键约定

| 动作 | 快捷键 | 说明 |
|---|---|---|
| 新建 | ⌘N | |
| 打开 | ⌘O | |
| 保存 | ⌘S | |
| 另存为 | ⇧⌘S | |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z | 编辑态走 `NSTextView` undo，非编辑态走 `CommandBus`（现状已处理） |
| 剪切 / 复制 / 粘贴 | ⌘X / ⌘C / ⌘V | |
| 全选 | ⌘A | 画布选中全部节点 |
| 查找 | ⌘F | 打开搜索 |
| 查找下一个/上一个 | ⌘G / ⇧⌘G | |
| 移到左/右侧 | ⌘← / ⌘→ | 仅一级枝，非编辑态 |
| 放大/缩小 | ⌘+ / ⌘− | |
| 实际大小 | ⌘0 | scale=1 |
| 适应画布 | ⇧⌘0 | |

---

## 3. 行为细则

1. **动态使能**（HIG Rule 1.3）：无选中时剪切/复制/删除禁用；标题反映数量（「删除 3 项」）。
2. 菜单项 = 命令唯一入口；工具条/右键菜单复用同一逻辑，**不另写**。
3. 编辑态与命令态的 Undo/Redo 分流已实现（`DocumentCommands`），保持。
4. 全部动作有快捷键（HIG Rule 1.2）。
