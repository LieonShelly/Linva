# YMind 代码检索约束（MCP · CodeGraph）

## 强制约束

**代码检索一律使用 CodeGraph MCP（`codegraph_explore`），不得用文本方式（grep / Glob / Read 逐文件）去人工翻代码兜底。**

- CodeGraph 的知识库索引位于 **`YMindApp/.codegraph`**（SQLite：`codegraph.db`）。
- 由于仓库根不在索引根，CodeGraph MCP 调用时**必须显式传 `projectPath: "YMindApp"`**（或 `YMindApp/.codegraph` 往上可达的路径），否则服务器没有默认项目、会回答不了。
- 一次 `codegraph_explore` 返回符号源 + 调用路径 + 波及面，替代「grep + Read 循环」这一轮查询。

## 何时必须用 CodeGraph

- 问「某符号 / 某功能怎么工作」——先 `codegraph_explore`
- 定位 bug / 找字段 / 找定义与调用方
- 改动前确定波及范围（调用路径、blast radius）
- 调查代码区 / 架构

## 何时可以不用（明确例外）

- 查目录结构 / 文件名 / 待检索清单 → `glob` / `read`（目录）
- 纯文本层级匹配、Mermaid / 文档内容 → 常规工具
- 项目还没有索引，或索引缺失时：用内置工具（Read / Grep / Glob）完成，不要擅自跑索引；索引属用户决策。

> 与 `.agents/AGENTS.md` 的「优先用 codegraph mcp 检索代码」一致，此处把具体路径与调用方式钉死，避免模型误用。