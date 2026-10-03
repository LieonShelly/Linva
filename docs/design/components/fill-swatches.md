# YMind — Component Spec: FillSwatches（填色组）

> 工具条色点组：5 色 + 默认清除。现状：`FillSwatches.swift`，色值经 `NodeFillStyle.swatch(_:)`。
> 引用 token：`--s-fill-swatch`、`--p-accent`、`--p-danger`。

---

## 1. 结构

圆形色点 × 6：5 色（sage/sky/sand/rose/lilac）+ 清除（斜线）。点直径 16pt，间距 6pt。

---

## 2. 状态表

| 状态 | 视觉 | 行为 |
|---|---|---|
| **默认** | 实心 token 色，1px 次级描边 | 点击设为该色 |
| **Hover** | `scale(1.08)` 轻微放大 | `--m-fast` |
| **激活（当前 fill）** | 2px accent 描边（外扩 3pt） | 单选时该节点 fill 对应的点激活 |
| **清除点激活** | 斜线点 accent 描边 | 当前无 fill 时激活 |
| **禁用（无选中）** | `opacity .35` | 不可点 |
| **多选不一致** | 无激活点 | 点任意色 → 全部设同色 |

---

## 3. 行为细则

1. 单选：当前 fill 对应点激活；全 nil 则清除点激活。
2. 多选：fill 一致 → 激活；不一致 → 无激活。
3. 无选中 → 全部禁用（现状 `canSetFill`）。
4. 复制粘贴保留 fill（现状：剪贴板快照含 fill）。

---

## 4. 无障碍

- 每个色点有 `accessibilityLabel`（如「填色 sage」）——现状用 `.help`，补齐 label。
- 激活状态不只靠颜色（加描边环），VoiceOver 读出选中态。
