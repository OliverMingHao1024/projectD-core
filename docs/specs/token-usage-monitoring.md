# Codex／Claude Token 用量監控

- 狀態：approved / Phase 1 contract + Codex local ledger ingestion implemented
- Parent tickets：[#38](https://github.com/OliverMingHao1024/projectD-core/issues/38)–[#44](https://github.com/OliverMingHao1024/projectD-core/issues/44)
- 實作順序：identity/event contract → Codex ledger → Claude ledger → source-side export gate → cross-device merge → reports → rollout

## Outcome

以同一份 provider-neutral contract 監控 Codex 與 Claude Code 的 token 用量，能辨識本機
使用的帳號、裝置與工作／家用環境，同時避免保存對話內容或把真實 email 匯出。

監控必須是確定性本機處理，不新增模型呼叫，也不把報表注入 AGENTS、CLAUDE 或其他
session-init context。

## Phase 1 contract

Phase 1 將私人帳號來源、裝置來源與可持久化事件拆成三個邊界：

1. `.local/governance/usage-account-profiles.json` 是 Git-ignored 的私人帳號對照檔。
   `account_id` 是一次生成後保存的隨機 ID；同一 Provider 帳號在工作與家用電腦必須使用
   同一筆帳號資料，才能安全彙總。
2. `.local/governance/usage-device.json` 是每台電腦獨立的裝置檔。不得在兩台電腦之間複製；
   工作與家用電腦必須有不同 `device_id`。
3. 可持久化的 identity snapshot 與 usage event 只包含 `account_id`、alias、provider、
   device、environment、billing source、plan availability 與用量 metadata；不包含 email、
   organization、prompt、response、tool arguments、tool output 或 credential。

帳號 ID 與裝置 ID 可使用下列離線函式建立；函式只呼叫本機亂數 UUID，不使用網路或模型：

```powershell
Import-Module scripts/lib/UsageContract.psm1 -Force
New-ProjectDUsageIdentifier -Kind Account
New-ProjectDUsageIdentifier -Kind Device
```

### 帳號 profile 範例

範例只能使用測試 email；真實值只可寫入 `.local/`：

```json
{
  "schema_version": 1,
  "accounts": [
    {
      "provider": "codex",
      "account_id": "acct_11111111111111111111111111111111",
      "alias": "personal-codex",
      "aliases": ["codex-personal"],
      "email": "codex@example.test"
    },
    {
      "provider": "claude",
      "account_id": "acct_22222222222222222222222222222222",
      "alias": "work-claude",
      "aliases": ["claude-work"],
      "email": "claude@example.test"
    }
  ]
}
```

### 裝置 profile 範例

```json
{
  "schema_version": 1,
  "device_id": "dev_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "environment": "work"
}
```

## Identity rules

- Codex `account/read` 的 `chatgpt`、`apiKey` 與 `amazonBedrock` 分別正規化為
  `subscription`、`api-key` 與 `third-party-cloud`。
- Claude `claude.ai` + `firstParty` + subscription type 才能成為已辨識訂閱；API 計費環境
  與 Bedrock／Vertex／Foundry routing 分別維持 `api-key` 與 `third-party-cloud`。
- 只有 Provider 與 email 同時匹配本機 profile 時才輸出 `verified`。
- 無法辨識時輸出 `unknown`；與呼叫者提供的 expected account 不一致時輸出 `mismatch`。
  兩種狀態都強制將 `account_id` 與 alias 設為 `null`，不得沿用前一次值。
- Email 只參與來源端比對，不會進入 identity snapshot 或 usage event。

## Usage event rules

所有 Provider 共用下列欄位：

- `input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `reasoning_tokens`
- `cache_creation_tokens`
- `estimated_cost_usd`

每個欄位都使用 `{ "status": "observed", "value": ... }` 或
`{ "status": "unavailable", "value": null }`。Provider 未提供的值不得寫成 0 或推估值。
`estimated_cost_usd` 即使可取得也只代表 Provider／collector 提供的估算，不代表帳單或 quota。
事件也必須保留 Provider 提供的 `session_id` 與 `turn_id`，供本機重播去重與跨裝置彙整。

Canonical schema：

- `evals/schemas/usage-account-profiles.schema.json`
- `evals/schemas/usage-device-profile.schema.json`
- `evals/schemas/usage-events.schema.json`
- `evals/schemas/codex-usage-projection.schema.json`
- `evals/schemas/codex-quota-projection.schema.json`
- `evals/schemas/codex-quota-snapshot.schema.json`

Canonical module：`scripts/lib/UsageContract.psm1`。

## Codex local ledger

Codex importer 接受 collector 在來源端合併後的 completed-turn metadata projection。其欄位對應
Codex App Server 的 `turn/completed` 與 `thread/tokenUsage/updated`：後者提供 `threadId`、
`turnId` 與本回合 `last` token breakdown。Projection schema 不允許 prompt、response、tool
arguments、tool output、email、quota 或 rate-limit 欄位。

Importer 只讀已存在的本機 JSON，不啟動 Codex、Claude、App Server 或任何模型，也不進行網路
呼叫。每個 `thread_id + turn_id` 會產生確定性的事件 ID；相同內容重播不重複寫入，同一 ID
若出現不同內容則 fail closed。Ledger 使用單寫入者 lock 與同目錄 durable replacement，且只允許
寫入 `ProjectRoot/.local/usage/*.jsonl`。

預設本機檔案：

- `.local/capture/codex-turn.json`：已消毒的 completed-turn projection。
- `.local/capture/codex-account-read.json`：來源端 `account/read` 結果，只用於本機 email 比對。
- `.local/usage/codex-ledger.jsonl`：不含 email 與對話內容的 raw usage ledger。
- `.local/usage/codex-quota-snapshot.json`：獨立、去識別化的最新 quota window snapshot。

匯入範例：

```powershell
pwsh -NoProfile -File scripts/codex-usage-import.ps1 `
  -ProjectionPath .local/capture/codex-turn.json `
  -AccountReadPath .local/capture/codex-account-read.json
```

只有 identity 為 `verified` 時才會寫入。Codex 官方 quota/rate-limit window 應另由
`account/rateLimits/read` 保存；ChatGPT 帳號的 aggregate token activity 則由
`account/usage/read` 取得。兩者都不會進入 per-turn ledger，也不得拿來替代本機 turn 診斷。
Quota collector 先將官方回應縮減為 `codex-quota-projection.schema.json`，再用獨立入口保存：

```powershell
pwsh -NoProfile -File scripts/codex-quota-import.ps1 `
  -ProjectionPath .local/capture/codex-quota.json `
  -AccountReadPath .local/capture/codex-account-read.json
```

Quota snapshot 只保存 limit/window ID、使用百分比、window 長度與 reset 時間，不保存 credits
描述、方案訊息、email 或 per-turn token 欄位；命令輸出也只回報 `inserted`、`updated` 或
`replayed` 狀態，與 token ledger 分開呈現。

## Verification

```powershell
pwsh -NoProfile -File scripts/tests/usage-contract.contract.ps1
pwsh -NoProfile -File scripts/tests/codex-usage-ledger.contract.ps1
pwsh -NoProfile -File scripts/tests/claude-switch-account.contract.ps1
pwsh -NoProfile -File scripts/projectd-check.ps1 -SkipFleet -SkipGlobal -SkipWiring
```

Claude 帳號 Status 的穩定公開入口是：

```powershell
pwsh -NoProfile -File scripts/claude-account.ps1 -Action Status
```

此入口只委派到 canonical `claude-switch-account` Skill，不複製驗證邏輯。

## Current boundary

目前已建立 contract 與 Codex completed-turn 本機 ingestion seam，但尚不修改使用者層級的
Codex OTel 設定，也不啟動 Codex App Server、collector、Claude monitoring、跨裝置同步或報表。
Live capture 與 rollout 留在 #44；後續 tickets 必須沿用本契約，且所有 raw ledger 仍只保存在
Git-ignored 的本機資料區。

## References

- [Codex App Server account endpoints](https://learn.chatgpt.com/docs/app-server)
- [Codex observability and telemetry](https://learn.chatgpt.com/docs/config-file/config-advanced)
- [Claude Code monitoring usage](https://code.claude.com/docs/en/monitoring-usage)
- [Claude Code costs and usage](https://code.claude.com/docs/en/costs)
- [Identity and event contract ticket #38](https://github.com/OliverMingHao1024/projectD-core/issues/38)
