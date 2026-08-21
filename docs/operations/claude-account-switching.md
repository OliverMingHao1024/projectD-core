# Claude 帳號切換維運指南

## 目的

`claude-switch-account` 用於在 Claude Code 的訂閱帳號之間安全切換。
它只使用 Claude 官方的互動登入流程，不保存、複製或搬移任何憑證。

本流程的固定原則：

- 只允許 Claude 訂閱帳號，不使用 API 額外計費。
- 每次登出與登入前都必須取得當次明確確認。
- 登入後必須比對目標 email，驗證失敗時停止，不自動重試。
- 不因用量耗盡而自動輪替帳號或改用 API。

## 帳號別名

| 正式別名 | 可用說法 | 用途 |
| --- | --- | --- |
| `work` | `工作` | 工作訂閱帳號 |
| `personal` | `個人` | 個人訂閱帳號 |

真實 email 只存放於本機設定：

```text
.local/governance/claude-account-profiles.json
```

`.local/` 已由 Git 忽略。不得將真實 email、token、API key、密碼或
Claude 憑證寫入 Canonical Skill、正式文件、測試資料或 Git。

## 日常使用

直接對 Agent 說：

```text
Claude 切換成個人
Claude 切到工作
Claude 現在是哪個帳號
```

也可以明確指定 Skill：

```text
使用 $claude-switch-account 切換到 personal
```

## 標準切換流程

1. 執行唯讀狀態檢查，確認目前使用 Claude 官方訂閱登入。
2. 解析 `work／工作` 或 `personal／個人`，比對本機設定的目標 email。
3. 若目標已是目前帳號，直接完成，不執行登出。
4. 若需要切換，顯示目前與目標帳號，取得一次新的明確確認。
5. 確認後執行 `claude auth logout`。
6. 執行 `claude auth login`，由使用者在官方頁面選擇帳號並完成授權。
7. 再次讀取狀態，要求登入 email 與目標完全相符。
8. 確認仍為 `claude.ai`、`firstParty`，且存在訂閱方案後才算完成。

Agent 不得替使用者在登入頁選擇帳號，也不得沿用前一次切換的確認。

## 訂閱與費用防線

下列任一狀況都必須停止：

- 偵測到 `ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN` 或外部 OAuth 環境值。
- 啟用 Bedrock、Vertex 或 Foundry 路由。
- `authMethod` 不是 `claude.ai`。
- `apiProvider` 不是 `firstParty`。
- 沒有可辨識的 Claude 訂閱方案。
- 登入後 email 與目標帳號不一致。

訂閱用量耗盡時，等待訂閱額度恢復或由使用者自行決定後續處理；不得
自動建立 API key、切換到按量計費或輪替其他帳號。

## 常見狀況

| 狀況 | 處理方式 |
| --- | --- |
| 目標帳號已登入 | 不登出，回報已是目標帳號。 |
| 官方登入頁未開啟 | 使用 Claude CLI 顯示的官方網址；不要改用第三方登入工具。 |
| 終端要求貼上代碼 | 只貼官方頁面產生的登入代碼，不提供密碼。 |
| 登入了錯誤帳號 | 停止並回報驗證失敗；重新切換前再次取得確認。 |
| 找不到帳號別名 | 檢查本機 profile 是否存在、JSON 是否有效、別名是否唯一。 |
| 偵測到 API 計費環境 | 停止切換，先移除或釐清相關環境設定。 |
| 訂閱用量已滿 | 不改用 API；等待額度恢復。 |

## 維護與驗證

Canonical Skill 位於：

```text
core/skills/claude-switch-account/
```

本機接線狀態可用下列命令檢查：

```powershell
& scripts/setup.ps1 -Mode Check
```

接線缺失時，經使用者允許後執行：

```powershell
& scripts/setup.ps1 -Mode Apply
```

行為契約測試：

```powershell
& scripts/tests/claude-switch-account.contract.ps1
```

完整 repository 檢查：

```powershell
& scripts/projectd-check.ps1 `
  -ProjectRoot D:\workspaces\projectD-core `
  -SkipFleet `
  -SkipGlobal
```

目前治理接線沒有單一 Skill 的獨立移除命令。不要直接刪除本機 junction；
需要移除時，先調整 canonical desired state 並經檢查後套用。只有要移除
整套 projectD 全域治理接線時，才使用 repository 提供的完整 uninstall 流程。

## 相關檔案

- `core/skills/claude-switch-account/SKILL.md`：Agent 操作規則。
- `core/skills/claude-switch-account/scripts/claude-account.ps1`：正式狀態檢查入口。
- `core/skills/claude-switch-account/scripts/claude-account-core.ps1`：驗證核心。
- `scripts/tests/claude-switch-account.contract.ps1`：契約測試。
- `.local/governance/claude-account-profiles.json`：Git ignored 的本機帳號別名。
