# Matt Skills 修改方案

## 背景

移除围绕 Issues Tracker 的 skills（`teach`、`triage`、`setup-matt-pocock-skills`、`resolving-merge-conflicts`、`ask-matt`），放弃 GitHub/Linear 等外部 issue tracker，转而以 `docs/mattpocock/features/` 下的本地 Markdown 文档作为工作单元载体。

`wayfinder` 于后续带回，同样魔改为本地模式：地图与决策 ticket 落在 `docs/mattpocock/features/<feature-slug>/` 下，不依赖 issue tracker（见第 6 节）。

## 文档路径约定

```
docs/mattpocock/features/<feature-slug>/
├── spec.md                              # 功能规格（PRD）
├── map.md                               # wayfinder 地图（规划期工件，可选）
├── tickets/
│   ├── 01-xxx.md                        # 按依赖排序的垂直切片
│   ├── 02-yyy.md
│   └── ...
└── wayfinding/
    ├── 01-xxx.md                        # wayfinder 决策 ticket（问题/决策，非建造切片）
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

### 1. to-spec (`to-spec/SKILL.md`)

**当前行为**：合成 spec → 发布到 issue tracker → 打 `ready-for-agent` 标签

**修改**：

| 位置 | 改动 |
|---|---|
| 整体 | 删除所有对 `/setup-matt-pocock-skills` 的引用 |
| 步骤 2-3 | 删除 "publish it to the project issue tracker. Apply the `ready-for-agent` triage label" |
| 步骤 2-3 替换 | 改为 "write the spec to `docs/mattpocock/features/<feature-slug>/spec.md`" |
| 模板 | 在 spec 模板头部添加 frontmatter：`---\nstatus: todo\n---\n` |

---

### 2. to-tickets (`to-tickets/SKILL.md`)

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

### 3. implement (`implement/SKILL.md`)

**当前行为**：基于 spec 或 tickets 实现，缺少文档定位逻辑

**修改**：

| 位置 | 改动 |
|---|---|
| 开头 | 添加定位逻辑：在 `docs/mattpocock/features/<slug>/tickets/` 下找到下一个 `status: todo` 且所有 `blocked_by` 均为 `done` 的 ticket |
| 完成时 | ticket 完成后自动更新 frontmatter `status: done`，并将 acceptance criteria 的 `- [ ]` 勾为 `- [x]` |
| spec 联动 | 当该 feature 下所有 ticket 均为 `done` 时，更新 spec 的 `status: done` |

---

### 4. code-review (`code-review/SKILL.md`)

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

### 5. prototype (`prototype/SKILL.md` / `LOGIC.md` / `UI.md`)

**当前行为**：第 6 条规则写 "leave a context pointer to that branch on the implementation issue"

注：`SKILL.md` 中没有直接写这条规则，需要检查 `LOGIC.md` 和 `UI.md`。

**修改**：

| 位置 | 改动 |
|---|---|
| 第 6 条规则 | "implementation issue" → "对应的 ticket 文档" |
| 第 6 条规则 | 强调 push throwaway branch 到本地 git（而非远程），指针写在 ticket 文档中 |
| 第 6 条规则（wayfinder 回归后补充） | 指针位置泛化：指向正在解决的 ticket 文档（建造 ticket 在 `tickets/`，wayfinder 决策 ticket 在 `wayfinding/`） |

---

### 6. wayfinder (`wayfinder/SKILL.md`)

**当前行为**：地图 + 决策 ticket 全部建立在 issue tracker 上（label、child issue、native blocking、assign、resolution comment）

**修改**：整体重写为本地 Markdown 语义，保留骨架与哲学（plan-don't-do、refer-by-name、fog of war、out of scope、ticket types、每 session 至多解一个 ticket，research 除外）

**概念映射表**：

| tracker 概念 | 本地文件语义 |
|---|---|
| issue / 标签 `wayfinder:map` | `docs/mattpocock/features/<slug>/map.md`（路径即身份，无标签） |
| child issue | `wayfinding/<NN>-<name>.md`，与建造 `tickets/` 隔离（implement 扫描零冲突） |
| `wayfinder:<type>` 标签 | frontmatter `type: research \| prototype \| grilling \| task` |
| native blocking / frontier 查询 | `blocked_by` frontmatter（repo-root 相对路径）+ 扫描 `wayfinding/`：`status: todo` 且所有 blocker 为 `done` |
| assign（claim） | `status: todo → in-progress` 翻转即认领 |
| resolution comment + close | 追加 `## Resolution` 段 + `status: done` |
| 出界关闭（close off-scope） | `status: out-of-scope`（独立状态，不进 Decisions-so-far） |
| issue id / URL | `NN` 编号 + repo-root 相对路径，嵌在标题引用中 |
| tracker doc "Wayfinding operations" | 删除，本地约定直接写入 skill 本体 |

**关键行为变更**：

| 位置 | 改动 |
|---|---|
| 整体 | 删除 `/setup-matt-pocock-skills`、issue-tracker doc 引用 |
| 布局 | map 在 `features/<slug>/map.md`（frontmatter `status: in-progress \| done`，frontier 清空翻 `done`）；决策 ticket 在 `features/<slug>/wayfinding/<NN>-<name>.md` |
| ticket 模板 | frontmatter（`status` + `type` + `blocked_by`）+ `# NN — <Title>` + `## Question`（区别于建造 ticket 的 `## What to build`） |
| 认领 | 开工前翻 `status: in-progress`，完工翻 `done` |
| resolution | 答案追加为 `## Resolution` 段；map 的 Decisions-so-far 每行 `- [<标题>](<相对路径>) — 一句话摘要`（map is index, not store） |
| research ticket | /research 子代理并行，findings 直接作为 Resolution；throwaway `research/<name>` 本地分支承载探索临时文件（与 prototype 规则 6 一致） |
| 接线 | 单遍完成（本地路径创建时即已知，无需 tracker id 两遍接线），编号按依赖序 01 起 |
| 并行 | 其他 session 可能同时编辑同一批文件，改动前重读；`in-progress` 即认领 |
| handoff | 地图走完（frontier 清空、map 翻 `done`）即路已清晰，自然衔接 to-spec → to-tickets → implement；to-spec **不读取** map（相邻而非接线） |

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
6. `wayfinder` — 带回后整体重写（含 prototype 规则 6 联动补充）

工作流顺序（skill 实际调用链）：`wayfinder`（探路）→ `to-spec` → `to-tickets` → `implement` → `code-review`
