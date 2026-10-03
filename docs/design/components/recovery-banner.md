# YMind — Component Spec: RecoveryBanner（恢复横幅）

> SwiftUI 顶部横幅，启动时检测到未保存草稿。现状：`RecoveryBannerView.swift`。
> 引用 token：`--c-popover-*`、`--p-danger`。

---

## 1. 结构

```
[⚠ 检测到上次未保存的更改                                    ]
[  「标题」 · 文件名 · 最近自动保存 12:30 · 5 处修改未写盘        ]
[                              [忽略（丢弃草稿）] [恢复更改]      ]
```

| 元素 | 规格 |
|---|---|
| 图标 | `exclamationmark.triangle.fill` 黄 |
| 标题 | headline |
| 摘要 | caption 次级色 |
| 动作 | 忽略（默认）/ 恢复更改（borderedProminent） |

---

## 2. 状态表

| 状态 | 行为 |
|---|---|
| **显示** | 启动扫描到最新副本时（`scanForRecovery`） |
| **恢复** | 载入草稿，标记未保存 |
| **忽略** | 清空副本，载入最近正式版 |
| **无副本** | 不显示 |

---

## 3. 行为细则

1. 只显示**最新**一个副本。
2. 恢复/忽略均不入命令栈（现状）。
3. 摘要信息：根文本 · 原文件名 · 保存时间 · 修改数。
