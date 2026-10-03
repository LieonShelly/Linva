# YMind — Component Spec: BranchToggle（分叉控件）

> 折叠/展开控件，Metal 层绘制。现状：`LayoutConstants.branchToggle*` + `BranchToggleAtlas`。
> 引用 token：`--c-toggle-*`（design-tokens.md §4.3）。

---

## 1. 结构

节点边缘外 18pt（`branchToggleGap`）处的圆形/胶囊控件。展开态白底 + accent 描边 + 「−」；折叠态实心 accent + 白字 + 隐藏数量（如「−5」）。

| 参数 | 值 | 映射 |
|---|---|---|
| 视觉半径 | 11pt | `LayoutConstants.branchToggleVisualRadius` |
| 命中半径 | 14pt | `LayoutConstants.branchToggleHitRadius` |
| 到节点间隙 | 18pt | `LayoutConstants.branchToggleGap` |
| 高度 | 22pt | 视觉半径 × 2 |

---

## 2. 状态表

| 状态 | 底 | 描边 | 文字 | 动效 |
|---|---|---|---|---|
| **展开** | `--p-node` 白底 | accent 55% | 「−」accent | — |
| **展开 hover** | accent-soft 80% 混白 | accent | 「−」accent | `scale(1.1)` `--m-fast` |
| **展开 active** | — | accent | 「−」 | `scale(0.96)` |
| **折叠** | `--p-accent` 实心 | 同底 | 「＋N」白，等宽数字 | — |
| **折叠 hover** | accent 加深 | — | 白 | `scale(1.1)` |

### 2.1 加号/减号语义（关键约定）

**图标表示「点击后的动作」**，不是当前状态（与 `BranchToggleAtlas.label` 一致）：

- **折叠态显示「＋N」** → 点击会**展开**整棵子树；`N` = 隐藏的后代节点数（无子代隐藏时仅「＋」）。
- **展开态显示「−」** → 点击会**折叠**。
- 反之显示「−」会让用户误以为「点击会展开、当前是折叠」——**禁止**。

---

## 3. 行为细则

1. 仅「有子节点」的节点显示（根节点左右两侧各一个；普通节点单侧，按 side）。
2. 折叠 → 整枝淡出收缩到控件（`motion-tokens.md §4.4`）；控件转实心。
3. 命中区 = 视觉外框外扩余量（现状 `branchToggleHitContains` 逻辑，保持）。
4. 数字 `−N` 随位数增长胶囊宽，封顶到节点间隙（现状逻辑）。

---

## 4. 无障碍

- 折叠状态用「−N 数字徽标 + 实心」双重表达（不只颜色）。
- 可被 VoiceOver 聚焦，读出「折叠，隐藏 N 个子主题」。
