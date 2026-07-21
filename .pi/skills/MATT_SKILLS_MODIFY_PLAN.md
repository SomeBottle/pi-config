# Matt Skills 修改方案

## 背景

移除围绕 Issues Tracker 的 skills（`teach`、`triage`、`setup-matt-pocock-skills`、`resolving-merge-conflicts`、`ask-matt`、`wayfinder`），放弃 GitHub/Linear 等外部 issue tracker，转而以 `docs/mattpocock/features/` 下的本地 Markdown 文档作为工作单元载体。

## 文档路径约定

```
docs/mattpocock/features/<feature-slug>/
├── spec.md                              # 功能规格（PRD）
└── tickets/
    ├── 01-xxx.md                        # 按依赖排序的垂直切片
    ├── 02-yyy.md
    └── ...
```

### Spec 文档模板

```markdown
---
status: todo | in-progress | done
---

## Problem Statement
## Solution
## User Stories
## Implementation Decisions
## Testing Decisions
## Out of Scope
## Further Notes
```

### Ticket 文档模板

```markdown
---
status: todo | in-progress | done
blocked_by:
  - docs/mattpocock/features/<slug>/tickets/<NN>-<name>.md
  - ...
---

# NN — Ticket Title

## What to build
...

## Acceptance criteria
- [ ] ...
- [ ] ...
```

---

## 各 Skill 修改详情

### 1. to-spec (`D:\Projects\pi-config\.pi\skills\to-spec\SKILL.md`)

**当前行为**：合成 spec → 发布到 issue tracker → 打 `ready-for-agent` 标签

**修改**：

| 位置 | 改动 |
|---|---|
| 整体 | 删除所有对 `/setup-matt-pocock-skills` 的引用 |
| 步骤 2-3 | 删除 "publish it to the project issue tracker. Apply the `ready-for-agent` triage label" |
| 步骤 2-3 替换 | 改为 "write the spec to `docs/mattpocock/features/<feature-slug>/spec.md`" |
| 模板 | 在 spec 模板头部添加 frontmatter：`---\nstatus: todo\n---\n` |

---

### 2. to-tickets (`D:\Projects\pi-config\.pi\skills\to-tickets\SKILL.md`)

**当前行为**：拆 ticket → 发布到 tracker（本地 `.scratch/` 或 GitHub/Linear）

**修改**：

| 位置 | 改动 |
|---|---|
| 整体 | 删除所有对 `/setup-matt-pocock-skills` 的引用 |
| 步骤 5 | 删除 GitHub/Linear 发布逻辑，保留本地文件模式 |
| 步骤 5 | 本地输出路径改为 `docs/mattpocock/features/<feature-slug>/tickets/<NN>-<slug>.md` |
| 模板 | ticket 头部改为 frontmatter 格式（`status` + `blocked_by`） |
| 模板 | `blocked_by` 使用 repo 根路径（如 `docs/mattpocock/features/<slug>/tickets/01-xxx.md`） |
| 模板 | Acceptance criteria 保留 `- [ ]` 格式 |
| 步骤 4 | 保留 "work the frontier" 策略，用 `/implement` 逐 ticket 推进 |
| 标签 | 删除所有 `ready-for-agent` 引用 |

---

### 3. implement (`D:\Projects\pi-config\.pi\skills\implement\SKILL.md`)

**当前行为**：基于 spec 或 tickets 实现，缺少文档定位逻辑

**修改**：

| 位置 | 改动 |
|---|---|
| 开头 | 添加定位逻辑：在 `docs/mattpocock/features/<slug>/tickets/` 下找到下一个 `status: todo` 且所有 `blocked_by` 均为 `done` 的 ticket |
| 完成时 | ticket 完成后自动更新 frontmatter `status: done`，并将 acceptance criteria 的 `- [ ]` 勾为 `- [x]` |
| spec 联动 | 当该 feature 下所有 ticket 均为 `done` 时，更新 spec 的 `status: done` |

---

### 4. code-review (`D:\Projects\pi-config\.pi\skills\code-review\SKILL.md`)

**当前行为**：两轴审查（Standards + Spec），从 commit message 中的 issue 引用查找 spec

**修改**：

| 位置 | 改动 |
|---|---|
| 整体 | 删除 `/setup-matt-pocock-skills` 引用 |
| 整体 | 删除 `docs/agents/issue-tracker.md` 引用 |
| 步骤 2 | 删除 "Issue references in the commit messages (`#123`...)" 查找方式 |
| 步骤 2 | 新增优先查找 `docs/mattpocock/features/` 下匹配当前分支名或 feature slug 的 spec |
| 步骤 2 | 保留用户传参和询问用户作为 fallback |

---

### 5. prototype (`D:\Projects\pi-config\.pi\skills\prototype\SKILL.md` / `LOGIC.md` / `UI.md`)

**当前行为**：第 6 条规则写 "leave a context pointer to that branch on the implementation issue"

注：`SKILL.md` 中没有直接写这条规则，需要检查 `LOGIC.md` 和 `UI.md`。

**修改**：

| 位置 | 改动 |
|---|---|
| 第 6 条规则 | "implementation issue" → "对应的 ticket 文档" |
| 第 6 条规则 | 强调 push throwaway branch 到本地 git（而非远程），指针写在 ticket 文档中 |

---

## 不改动的 Skills（已验证无 tracker/已移除 skill 引用）

- `tdd` — 无引用
- `codebase-design` — 无引用
- `diagnosing-bugs` — 无引用
- `domain-modeling` — 无引用
- `research` — 无引用
- `find-docs` — 无引用
- `grill-me` — 无引用
- `grill-with-docs` — 无引用
- `improve-codebase-architecture` — 无引用
- `writing-great-skills` — 无引用
- `handoff` — 无引用（"issues" 仅为泛指标签列表，非 tracker 依赖）

---

## 执行顺序

1. `to-spec` — 工作流入口，先改
2. `to-tickets` — 依赖 to-spec 的输出路径
3. `implement` — 依赖 to-tickets 的输出路径
4. `code-review` — 依赖上述 spec/ticket 路径
5. `prototype` — 末端引用，最后改
