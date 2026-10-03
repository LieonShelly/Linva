# YMind — Component Spec: Toolbar（工具条）

> SwiftUI 壳层，统一标题栏工具条。HIG：工具条是**次要命令面**，保留高频操作；低频移入菜单/右键。
> 决策：**收敛常用 + 溢出其余**（用户拍板）。工具栏保持系统材质（`--s-chrome-bg`）。

---

## 1. 布局结构

`ToolbarItemGroup(.automatic)` 放高频；`.secondaryAction` 放下拉菜单收纳低频。

```
[ 子主题 | 同级 | 删除 | 填色5点+清除 | ┊ 布局切换 ]   …   [ 搜索 | 缩放 % | 放大/缩小/适应 | 溢出▾ ]
  ▲ 高频                                   ▲ 低频收进 ▾ 菜单
```

### 主区（automatic）— 保持高频
| 项 | 图标 (SF) | 快捷键 | 使能 |
|---|---|---|---|
| 子主题 | `arrow.turn.down.right` | Tab | 有选中 |
| 同级主题 | `plus.rectangle.on.rectangle` | Return | 有选中 |
| 删除 | `trash` | Delete | 有选中 |
| 填色组 | 5 色点 + 清除 | — | 有选中 |
| 布局切换 | segmented（辐射/逻辑） | — | 常驻 |

### 次区（secondaryAction / 溢出）— 低频收进菜单
| 项 | 归处 |
|---|---|
| 剪切 / 复制 / 粘贴 | **Edit 菜单 + 右键菜单**（工具条移除） |
| 移到左侧 / 右侧 | **Edit 菜单 + 右键菜单** |
| 导出 Markdown / PNG | **File 菜单**（工具条移除，现有 File 菜单已含） |

> 现状工具条含剪切/复制/粘贴/改侧/导出，**本规格全部移出**，工具条瘦身为 5 组高频 + 缩放/搜索。

---

## 2. 状态表（工具条按钮）

| 状态 | 底 | 文字/图标 | 动效 |
|---|---|---|---|
| 默认 | 透明 | `--s-canvas-ink` | — |
| Hover | `--c-toolbar-btn-hover-bg`（浅 hover） | 同上 | `--m-fast` |
| 按下 | 略深 | 下压 1px | `--m-fast` |
| 禁用 | 透明 | 系统 `disabledControlTextColor` opacity .35 | — |
| 危险 hover（删除） | danger 12% 混 | `--s-danger` | `--m-fast` |

- 按钮高度 28pt（macOS 紧凑控件，非 iOS 大触控目标）。
- 用 `Label`（icon + 文字）兼顾可发现性与可访问标签。

---

## 3. 填色组（FillSwatches）

见 `fill-swatches.md`。5 色点 + 清除（斜线）。

---

## 4. 缩放组

`[− | 100% | + | 适应]`，居中「100%」用等宽数字（`.monospacedDigit`）。缩放百分比变化 `--m-base` 淡入淡出。

---

## 5. 无障碍

- 纯图标按钮必须 `accessibilityLabel`（HIG Rule 11.1）——现状多数有 `.help`，补齐 label。
- 布局切换 segmented 有 label。
- 溢出菜单项与菜单栏条目一致，防止「菜单里找不到」。
