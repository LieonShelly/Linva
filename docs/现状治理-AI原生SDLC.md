# Linva — AI 原生 SDLC 现状治理记录

**状态：** 持续维护的活文档（治理清单）  
**创建：** 2026-09-27  
**依据：** `docs/articles/the-ai-native-sdlc-playbook-中文版.html`（Anthropic 官方博客中文版）  
**对照：** `docs/架构现状.md`、`docs/关键技术点.md`、`.agents/`、`docs/superpowers/*`

> **用途**：把「基于手册理论依据的现状分析与改进项」固化为文档，逐项解决、逐项打标记，
> 作为后续工作的单一真源，避免模型上下文过长导致失忆。

---

## 1. 理论依据（手册核心，本文一切判断的基准）

1. **瓶颈迁移**：当代码（构建）不再是瓶颈、被压缩到小时级，瓶颈转移到两侧仍以人类速度运行的环节（规划、评审/测试、部署）。控制手段需跟上智能体的产出节奏。
2. **循环 + 已提交产物链**：SDLC 由线性流水线变为循环，交接靠产物提交自动触发。产物链 `intent.md → spec.md → plan.md → diff+测试 → 带评审结论的 PR → 事故记录` 同时是审计线索。人类注意力上移，集中在评审关卡。
3. **知识版本化、机器可读**：`CLAUDE.md`（约定/架构/常犯错误，犯两次错就回写）、技能 skills（建议性机构知识）、钩子 hooks（确定性强制）、评估 evals（智能体配置的回归测试）。
4. **控制分级**：技能（建议）→ 钩子（强制）→ 人类审批关卡（判断与问责）。`写代码的智能体不能批准自己`。从无前置依赖的「泥土行动」开始按依赖图采纳。

---

## 2. 现状评估

### 2.1 已对齐（无需处理）

| 手册 Play | Linva 现状 | 位置 |
|-----------|-----------|------|
| intent 捕获 | ✅ 已建 | `docs/prds/prd-linva-*` |
| spec / plan 产物链 | ✅ 已建 | `docs/superpowers/specs/`、`plans/` |
| CLAUDE.md 类知识文件 | ✅ 已建 | `.agents/AGENTS.md`、`rules/linva-apple-stack.md` |
| 技能（第三方） | ✅ 已装 37 个 | `.agents/skills/`（`npx skills`） |
| MCP / 构建 | ✅ 已配 | `.agents/mcp.json`（XcodeBuildMCP、xcode） |

### 2.2 差距项（治理清单见 §4）

| 编号 | 差距 | 手册依据 |
|------|------|---------|
| A | 目录/依赖规则靠约定，编译器不强制 | 钩子作为构建期护栏（技能让违规罕见，钩子让违规几乎不可能） |
| B | 缺 Linva 专属技能（本仓库自己的约定未编码） | 技能作为机构知识 |
| C | AGENTS.md 无「常犯错误」块、偏长 | CLAUDE.md（犯两次错就回写、控制在一页内） |
| D | 验证路径分散，无单命令 + 健康输出示例 | 反馈回路 |
| E | 无评审合规基准（REVIEW.md） | PR 评审回路对照 spec/plan |
| F | 无 evals / 度量 | 持续评估（当前单人阶段不建议做） |

---

## 3. 达标解释（A–F 做完 ≠ 符合手册所有标准）

> 本节澄清「达标」的含义，避免后续误以为 A–F 全做完就「符合手册所有标准」。

### 3.1 A–F 只覆盖手册的一小部分

| 手册阶段 / 行动 | A–F 覆盖？ | 说明 |
|---|---|---|
| 规划 intent.md 捕获 | ⚠️ 部分 | 项目有 PRD，但非手册的 intent.md 格式（提出者原话、机器可读、`intent/` 目录） |
| 设计 需求+设计合并 | ⚠️ 部分 | 有 spec，但未系统化「技能约束设计 + 标记关注区」 |
| 构建 plan.md 计划模式 | ❌ | 治理清单无 plan.md 工作流 |
| 构建 CLAUDE.md | ✅ C | 已精简 + 常犯错误 |
| 构建 技能 | ✅ B | linva-* 已建 |
| 构建 钩子 | ✅ A | build-phase 护栏 |
| 构建 并行会话/子智能体 | ❌ | 不在清单 |
| 测试 反馈回路 | ⚠️ D | 单一验证命令，尚未固化进 AGENTS.md 验证块 |
| 测试 CI evals | ⚠️ F | 清单标「暂缓/不做」 |
| 部署 AI PR 评审 | ❌ | 本地 app 无 PR 流程 |
| 部署 钩子作审批关卡 | ⚠️ | A 是 build 护栏，非 release 关卡 |
| 部署 CI/CD 集成 | ❌ 不适用 | 本地 macOS app |
| 维护 闭环监控 / 事故→intent | ❌ 不适用 | 无生产环境 |
| 维护 周期性扫描 / on-call | ❌ 不适用 | 无线上部署 |

### 3.2 手册自己不要求「全部照做」

- **「大多数组织介于这两列之间」**——传统与 AI 原生是两个端点，非二选一达标。
- **行动是模块化的**——「组织可依自身需求在不同时间优先改造不同阶段」，且有依赖图（clay play 起步）。
- 逐条全做既不必要也不现实。

### 3.3 很多标准对 Linva 不适用

手册面向**多人、企业、监管、有生产环境**的组织。Linva 是**单人本地 macOS 工具**：
- 无「生产环境」→ 部署/维护/监控/回滚/on-call 无意义
- 无多角色/监管 → 审批关卡、治理委员会无意义
- 无线上 CI/CD 流水线

对这些，「不适用」才是正确做法，硬套是过度工程（F 标暂缓、E 标低优先即此原因）。

### 3.4 对 Linva 的「达标态」（符合手册精神，而非逐条标准）

| 手册精神 | Linva 达标态 | 状态 |
|---|---|---|
| 知识版本化、机器可读 | AGENTS.md + linva-* 技能 + rules | ✅ 完成 |
| 钩子让违规几乎不可能 | 依赖边界 build-phase | ✅ 完成 |
| 反馈回路：会话自查 | 单一验证命令（D） | ⏳ 待做 |
| 已提交产物链作为审计线索 | PRD/spec/plan 已有，非 intent.md 格式 | ⚠️ 可维持或补 plan.md 基线 |
| 人类判断居于其上 | 单人开发天然满足 | ✅ |
| evals / 部署 / 维护 | 不适用，明确不做 | — |

**结论：** A–F 做完 = 把「构建 + 测试」里对 Linva 有意义的护栏全部落地，**在手册精神上达标**；**不是**字面「符合所有标准」——规划格式可再对齐，部署/维护因不适用而主动不做。

---

## 4. 治理清单（逐项解决，完成后打标记）

> 约定：**状态**取值 `🔲 待办` / `🟡 进行中` / `✅ 已完成`；**解决日期**填写 git 提交或完成当天。

### 优先级 P0（最高杠杆，不动产品功能，纯强化开发底座）

#### A. 依赖边界强制化
- **状态：** ✅ 已完成（2026-09-27）
- **目标：** 让 `docs/架构现状.md` §5 的依赖规则从「目录约定」变为「被强制」，违规即失败。
- **落地（方案二：校验脚本 + Xcode build phase）：**
  - 新增 `scripts/check-boundaries.sh`：按目录白名单扫描 `import`，违规退出码 1。
  - 白名单（严格收紧版，与实况核对）：Model/Commands 仅 `Foundation`；Layout `Foundation AppKit CoreGraphics CoreText`；Session `Foundation Combine CoreGraphics`；Render `Foundation AppKit CoreGraphics Metal MetalKit SwiftUI simd`；App `Foundation AppKit SwiftUI`。
  - 主 target 新增 build phase「依赖边界校验」，置于 Sources 之前；构建即红。
  - 主 target Debug/Release 设 `ENABLE_USER_SCRIPT_SANDBOXING = NO`。
- **验收（已通过端到端）：**
  - 干净构建 → 通过；
  - 在 `Model/Node.swift` 注入 `import SwiftUI` → `BUILD FAILED`，checker 报 `依赖违规 [Model]: SwiftUI`；
  - 还原后 → `BUILD SUCCEEDED`。
- **排查记录（坑）：** Xcode 26 默认开启用户脚本沙箱，`.sb` profile 会 `deny file-read* (subpath SRCROOT)`，导致 build phase 内脚本读不到源码、误报「通过」。必须 `ENABLE_USER_SCRIPT_SANDBOXING = NO` 才能让脚本读源码树。
- **解决日期：** 2026-09-27

#### B. Linva 专属技能沉淀
- **状态：** ✅ 已完成（2026-09-27）
- **目标：** 把本仓库「必须一致应用」的约定编码成 `.agents/skills/linva-*`，跨会话稳定。
- **落地（方案A + 独立目录，各含 SKILL.md 按领域拆 4 个）：**
  - `linva-command` — 加可逆命令：enum case → `applyForward` 分支 → undo/redo 闭包；哪些操作不入栈（相机/选中/搜索态）；现有命令清单。
  - `linva-codec-version` — `.linva` schema 升迁：`currentVersion` 递增、迁移、`sanitize` 的 `side` 消毒（仅根下一层）+ warnings。
  - `linva-layout-snapshot` — LayoutSnapshot/NodeFrame/EdgeGeometry 契约：Metal 只消费 Snapshot 不懂树；RadialLayout 的 side/折叠/BranchToggle 不变量。
  - `linva-render-text` — 文字纹理路径：AppKit 绘制 + 行翻转 + UV、Retina scale、脏缓存更新。
  - 全部登记到 `.agents/AGENTS.md`「Linva 专属技能」小节；独立目录不受 `npx skills update` 覆盖。
- **验收：** 新会话接手改树/加命令时读对应 skill 即遵守约定；frontmatter 触发条件清晰、与现有 skill 格式一致。
- **解决日期：** 2026-09-27

### 优先级 P1（低成本高回报，纪律性改进）

#### C. AGENTS.md 精简 + 常犯错误块
- **状态：** ✅ 已完成（2026-09-27）
- **目标：** 加「Claude 常犯的错误」区（针对 Linva），并把偏长的 skill 表收敛。
- **落地：**
  - `.agents/AGENTS.md` 从 108 行精简到 59 行（-45%）。
  - 删除 4 张第三方 skill 路由表（与 `rules/linva-apple-stack.md` 重复，且各 skill 自带 `description` 自动路由）→ 收敛为一行指向 rules + 画布优先序。
  - 保留：项目介绍、文档语言、MCP、Linva 专属技能表、更新命令、v1 范围。
  - 新增「**Claude 常犯的错误**」块：6 条实读代码的已知坑（绕命令栈、schema 不升版本、深层 side、删行翻转、Render 读 Model、新依赖不进白名单），各条指向对应 `linva-*` skill。
- **验收：** AGENTS.md 一页内可读；常犯错误条目与 `架构现状.md`/各 skill 已知坑一致。
- **解决日期：** 2026-09-27

#### D. 单一验证命令 + 健康输出示例
- **状态：** 🔲 待办
- **目标：** 固化一条本地单命令（如 `xcodebuild … build && test`）+ 预期健康输出，写进 AGENTS.md 验证块，让会话能自查。
- **验收：** 任何会话交付前跑该命令即可确认构建 + 测试状态。
- **解决日期：** —

### 优先级 P2（暂缓 / 当前阶段不做）

#### E. 评审合规基准（REVIEW.md）
- **状态：** 🔲 待办（低优先，单机无正式 PR 时价值有限；上 GitHub 协作再做）
- **解决日期：** —

#### F. evals / 度量
- **状态：** 🔲 待办（单人 macOS 工具做 evals 属过度工程；明确不做）
- **解决日期：** —

---

## 5. 处理顺序（默认执行路径）

```mermaid
flowchart LR
  A["A. 依赖边界强制"] --> B["B. Linva 专属技能"]
  B --> C["C. AGENTS.md 精简+常犯错误"]
  C --> D["D. 单命令验证"]
  D --> E["E. REVIEW.md（可跳过）"]
```

1. **先 A**：边界强制是根，后续加功能都受益，且是最贴手册「钩子」的一笔。
2. **再 B**：技能沉淀依赖 A 把边界说清，才能写进技能。
3. **后 C、D**：纪律性收尾，成本低。
4. **E、F**：视是否上协作 / 是否需要度量再定，可长期搁置。

---

## 6. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-09-27 | 初稿：基于手册理论依据 + `架构现状.md` 梳理现状，建治理清单 A–F |
| 2026-09-27 | **A 已完成**：`scripts/check-boundaries.sh` + Xcode build phase「依赖边界校验」，端到端验证通过 |
| 2026-09-27 | **B 已完成**：4 个 Linva 专属技能（`linva-command`/`linva-codec-version`/`linva-layout-snapshot`/`linva-render-text`），登记到 `.agents/AGENTS.md` |
| 2026-09-27 | **C 已完成**：`.agents/AGENTS.md` 精简 108→59 行 + 新增「Claude 常犯的错误」块 |
| 2026-09-27 | 新增 §3「达标解释」：澄清 A–F 做完≠符合手册所有标准；重编号 §3→4、§4→5、§5→6 |
