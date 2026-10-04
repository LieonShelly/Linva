# YMind 需求 Backlog（单一真源）

> 维护规则：每次 `ymind-pm` 探索结束必须更新本表状态。状态流：**探索中 → 就绪 → 进行中 → 搁置 / 砍掉**。「就绪」表示已产出需求包（需求文档 + 原型图），可移交 bmad-prd 写 PRD。

## 状态表

| 状态 | 课题 | 机会卡片 | 决策（ICE） | 备注 / 下一步 |
|------|------|----------|------------|--------------|
| **就绪** | 迁移闭环：导入（Markdown/OPML/FreeMind）+ 导出（Markdown/PNG/.ymind；已移除：PDF 导出不做）+ 自动保存/崩溃恢复 | [opportunities/2026-09-30-迁移闭环导入导出.md](opportunities/2026-09-30-迁移闭环导入导出.md) | 做（I9 C8 E6 → 12.0） | 打磨 v1 到「能正经用」：编辑→导入→导出→防丢闭环；含 FR-I1/I2/E1/E2/S1/S2。**本版不考虑付费/商业化**。PRD 已交付：[prd-ymind-import-export-2026-09-30](../../prds/prd-ymind-import-export-2026-09-30/prd.md)。下一步：开发 Agent 开工（specs → plans） |
| 搁置 | iCloud + 多文档文件库 | 同上（O3） | 5.3 | PRD 后置；单文档阶段价值有限，沙盒改造成本高 |
| 搁置 | AI 集成（MCP / BYOK） | 同上（O4） | 7.1 | 上架后 v1.1；`.ymind` JSON 对 MCP 友好，依赖外部生态与成本模型先想清 |
| 搁置 | 大纲视图 | 同上（O5） | 5.0 | 与导出/打印联动，可后置 |
| 搁置 | 图标 / 节点备注 / 富文本 | 同上（O6） | 4.0 | 上架后按用户反馈排（注：AppIcon 图标的「图标」≠ 节点图标，勿混） |
| **就绪** | 节点内嵌图片（图 + 文共存） | [opportunities/2026-09-30-节点图片功能.md](opportunities/2026-09-30-节点图片功能.md) | 做（I9 C9 E7 → 11.6） | 竞品成熟度基线；**排期已定 A（进 1.0，与迁移闭环并行）**。PRD 已交付：[prd-ymind-image-node-2026-09-30](../../prds/prd-ymind-image-node-2026-09-30/prd.md)（含并行接缝 FR-G6）。下一步：开发 Agent 开工 |
| **就绪** | 上架就绪（App Store 提交） | [launch-checklist-2026-09-30.md](launch-checklist-2026-09-30.md) | —（工程合规，非需求课题） | P0：AppIcon 填充 + 隐私清单 + 元数据；P1：崩溃实测 / 部署目标 / entitlements 确认。开发终端逐项销项 |
| **就绪** | 新增布局类型：逻辑图（总分树）+ 布局切换器 | [opportunities/2026-10-02-新增布局类型.md](opportunities/2026-10-02-新增布局类型.md) | 做（I8 C8 E5 → 12.8） | 产品本人拍板场景「总分归纳」（读书笔记/知识体系）；Codec v5 + LogicLayout + 工具栏切换器；**排期待拍板（推荐紧随 1.0）**。PRD 已交付：[prd-ymind-layout-2026-10-02](../../prds/prd-ymind-layout-2026-10-02/prd.md) |
| **就绪** | Node 连线样式：曲线 / 大括号 / 正交折线（全局一键切换） | [opportunities/2026-10-04-连线样式.md](opportunities/2026-10-04-连线样式.md) | 做（I7 C8 E7 → 8.0） | 竞品连线样式 = 成熟度基线；全局一种、一键切换、无损重绘、**随文档持久化 + 入命令栈**（产品本人拍板）。原型 `prototype/edge-style.html`。**PRD 已交付**：[prd-ymind-edge-style-2026-10-04](../../prds/prd-ymind-edge-style-2026-10-04/prd.md)。排期待拍板 |

## 变更记录

| 日期 | 变更 |
|------|------|
| 2026-09-30 | 建立 backlog（ymind-pm 技能配套） |
| 2026-09-30 | 首次探索「上架就绪 · 下一个需求」：调研 + 机会卡片落盘；**迁移闭环**决策「做」（就绪）；iCloud/AI/大纲/图标备注搁置 |
| 2026-09-30 | 产品本人拍板：本版**不考虑付费/商业化**，先打磨功能；卡片/原型/backlog 同步收紧 |
| 2026-09-30 | **PRD 已交付**：`docs/prds/prd-ymind-import-export-2026-09-30/`（prd.md + addendum.md），Fast path 出稿 |
| 2026-09-30 | 新探索「节点内嵌图片」：竞品标配（XMind/MindNode）证据 + 成本评估（E≈7，Codec v3 迁移 + Render 图片纹理为主）；**决策做**（ICE 11.6），需求包就绪（卡片 + image-node.html 原型），排期待拍板 |
| 2026-09-30 | 图片功能**排期定 A（进 1.0，与迁移闭环并行）**；PRD 已交付 `docs/prds/prd-ymind-image-node-2026-09-30/`（含并行接缝 FR-G6） |
| 2026-10-02 | 新探索「新增布局类型」：调研（XMind 11 结构清单 + 适用场景 [EVIDENCE]）+ 内部访谈（产品本人选「总分归纳」场景）+ 机会卡片 + ICE 决策**做**（12.8，逻辑图）；原型 `prototype/layout-switcher.html`；**排期待拍板（推荐紧随 1.0）** |
| 2026-10-02 | **PRD 已交付**：`docs/prds/prd-ymind-layout-2026-10-02/`（prd.md + addendum.md，bmad-prd Fast path），FR-L1…L5 + 验收要点；排期决策点仍开放（§9.1，推荐 A 紧随 1.0） |
| 2026-10-04 | 新探索「Node 连线样式」：外部调研（MindNode/Miro/SimpleMind/XMind/MindNoodle 连线样式均为全局一种 [EVIDENCE]）+ 内部访谈（动机=视觉+语义两者都要、作用域=全局、样式集=曲线+大括号+正交折线、成功=一键切换无损）+ 机会卡片 + ICE 决策**做**（9.3，连线样式）；原型 `prototype/edge-style.html`（浏览器验证三样式渲染 + 切换交互）；排期待拍板 |
| 2026-10-04 | **PRD 已交付**：`docs/prds/prd-ymind-edge-style-2026-10-04/`（prd.md + addendum.md，bmad-prd Fast path），FR-E1…E5 + 验收要点 + 原型对照；排期决策点仍开放（§9.1，推荐紧随 1.0） |
| 2026-10-04 | **PRD 修订**：产品本人拍板**连线样式持久化 + 入命令栈**（推翻原「会话态、不持久化」）；FR-E1 改文档字段 + Codec 迁移；新增 Codec 版本号与布局 PRD 协调点（§9.4）；ICE E 6→7（9.3→8.0）仍「做」 |

---

## 说明

- **探索中**：`ymind-pm` 正在内部访谈 / 外部调研，尚无机会卡片。
- **就绪**：机会卡片 + 原型图已产出，可移交 `bmad-prd`。
- **进行中**：PRD 已出，开发 Agent 已开工。
- **搁置 / 砍掉**：附原因，避免重复讨论失忆。