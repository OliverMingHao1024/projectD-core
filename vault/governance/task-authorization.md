---
type: governance
layer: L1
readAt: on-demand
trigger: 工具呼叫被 projectD runtime policy 拒絕，或需要請使用者發任務授權
---

# 任務授權：被擋時怎麼請使用者發授權

> 來源：實際反覆踩坑——agent 給錯授權指令、指令不完整，或指令沒送到使用者眼前。
> 腳本與分類規則的權威是 `scripts/governance-task-authorization.ps1` 與
> `scripts/lib/RuntimePolicy.psm1`；本頁只整理 agent 的做法，兩者不一致時以程式為準並回報。

## 0. 底線

- 授權只能由**使用者**在**自己開的互動式終端機**發。agent 不能自己跑發授權腳本
  （stdin 被 redirect 會被拒），也不能寫 `.local/governance/` 下的任何檔案。
- 指令必須在**主 checkout 根目錄**跑（即使 session 在 `.claude/worktrees/<name>`），
  用 `pwsh`。
- 給使用者的指令必須**可直接複製執行**：單行、完整參數、含 `-DecisionPath`、附上要親手
  輸入的確認字串。不要給「範本」讓使用者自己填。
- 只要求**最小**的授權；不確定要哪一種時，先查 decision 檔（第 2 步），不要猜。

## 1. 先問：真的需要授權嗎？

| 情況 | 正確做法 |
|---|---|
| 只是要讀東西 | 用 Read／Grep／Glob 工具，不要用 shell |
| shell 指令含 `>`、`<`、反引號、`$(...)`（例如 `2>/dev/null`），或任一段不在唯讀清單 | 改寫成唯讀形式；否則會被歸成 `command-execute`，要外部＋破壞性大授權 |
| reason code 含 `unclassified-effect` | **授權也放不行**，不要叫使用者發。換工具或路徑（例如：寫到專案根目錄外、寫 `.local/governance/`、未知工具／多數 MCP） |

唯讀 shell 清單（逐段比對）：`git status/log/diff/show/blame/...`、`ls`、`cat`、`head`、
`tail`、`wc`、`grep`、`rg`、`Get-ChildItem`、`Get-Content`、`Select-String`、`codegraph query` 類、
`gh pr view/list/checks` 類、`<tool> --version`。`Sort-Object`、`Where-Object` 等不在清單內。

## 2. 查出被擋的到底是什麼

1. 看錯誤訊息的 reason code（見第 5 步）。
2. 找本 session 的 deny decision：

   ```bash
   ls -t .local/governance/runtime-policy/claude | head -5
   ```

   （Codex 把 `claude` 換成 `codex`。）用 Read 打開，找 `decision.outcome = deny` 的那筆，
   記下 `request.capability`、`request.target_class`、`request.effect`、`task_ref` 與檔名。
   注意：這個 `ls` 本身也會寫一筆 `local-read` decision，所以最新那筆通常不是 deny。
3. 用下表對照，確認要哪個授權：

| 被擋的操作 | capability / target_class | 需要 |
|---|---|---|
| Write／Edit 一般專案檔 | `workspace-write` / `workspace-file` | 單組授權 |
| Write／Edit 治理路徑：`.claude/`（含 worktree）、`.codex/`、`core/constitution/`、`vault/governance/`、`scripts/governance-*`、`scripts/lib/{RuntimePolicy,GovernanceCommon}.psm1`、`scripts/projectd-check.ps1`、`scripts/tests/governance-*`、`evals/governance-assets.json`、`evals/schemas/governance-*`、`.github/workflows/governance*` | `repository-mutate` / `governance-control` | 單組或 `governance-dev` |
| `git add/commit/merge/rebase/checkout/switch/branch/tag/restore/cherry-pick`、寫 `.git/` | `repository-mutate` / `repository-state` | 單組或 `governance-dev` |
| `git push/pull`、`gh pr create/merge/...` | `repository-mutate` / `repository-state`，external | `-AllowExternal`；force push／reset／merge／delete 另加 `-AllowDestructive`（L0 高風險，先確認） |
| 其他 shell 指令 | `command-execute` / `command-environment` | `-AllowExternal -AllowDestructive`；**先試第 1 步改寫，最後手段** |
| MCP／web 寫入工具 | `external-write` / `external-service` | 單組，依 effect 加旗標 |

`-CapabilitySet governance-dev` = 前三列三組（皆非外部、非破壞性），適合「改治理檔＋commit」
的工作；不能涵蓋 push 或 `command-execute`。

## 3. 給使用者的指令（照抄格式）

單組：

```bash
pwsh -NoProfile -File scripts/governance-task-authorization.ps1 -HostName claude -Capability <capability> -TargetClass <target_class> -ExpiresInMinutes 30 -DecisionPath ".local\governance\runtime-policy\claude\decision-call-<id>.json" -ExplicitUserAuthorization
```

確認字串：`AUTHORIZE claude <capability> <target_class>`

套組：

```bash
pwsh -NoProfile -File scripts/governance-task-authorization.ps1 -HostName claude -CapabilitySet governance-dev -ExpiresInMinutes 30 -DecisionPath ".local\governance\runtime-policy\claude\decision-call-<id>.json" -ExplicitUserAuthorization
```

確認字串：`AUTHORIZE claude SET governance-dev`

必附說明：

- 「請在你自己開的終端機、`D:\workspaces\projectD-core` 根目錄執行」。
- 提示會顯示 `task_ref=...`，請使用者核對它等於第 2 步記下的 `task_ref`。
- 跑完請使用者回覆，agent 再重試原操作。

## 4. 送達：指令要讓使用者真的看得到

- Claude desktop app：指令與確認字串放在**呼叫 `mcp__ccd_turn__wrap_up` 之後的最後訊息**。
  寫在 wrap_up 之前的文字可能被縮成摘要，使用者看不到指令。
- 每條指令一個 fenced code block，不要混在句子裡。

## 5. 常見 reason code 與處置

| reason code | 意思 | 處置 |
|---|---|---|
| `task-authorization-required` | 本 session 沒有有效授權 | 照第 2–4 步請使用者發 |
| `capability-not-granted` | 有授權但不含這組 capability/target_class | 再發缺的那組（同 task_ref 會合併，舊的不用重發） |
| `external-effect-not-granted` / `destructive-effect-not-granted` | 缺 `-AllowExternal` / `-AllowDestructive` | 只能用單組授權加旗標；先確認真的需要 |
| `authorization-envelope-expired` | 過期 | 重發 |
| `authorization-envelope-policy-mismatch` | policy bundle 被改過（`RuntimePolicy.psm1`、`GovernanceCommon.psm1`、`governance-host-operation-hook.ps1`、`governance-task-authorization.ps1`、兩份 runtime/authorization schema） | 改完這些檔後一定要重發；這是預期行為 |
| `authorization-envelope-identity-mismatch` | 授權發給了別的 session | 用正確 `-DecisionPath` 重發 |
| `unclassified-effect` | 無法分類 | 授權無效，見第 1 步 |

## 6. 不要做的事

- 不要省略 `-DecisionPath`：多個 session 並行時會發錯 session 或被拒。
- 不要叫使用者在 agent 的 Bash／PowerShell 工具裡跑，也不要在 worktree 目錄跑。
- 不要因為一條 shell 指令被擋，就直接要 `command-execute` 大授權。
- 不要叫使用者授權 `unclassified-effect`，也不要嘗試編輯 `.local/governance/` 繞過。
- 不要把 host（Claude Code）的權限提示當成 projectD 授權。
