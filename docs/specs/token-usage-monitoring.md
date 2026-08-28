# Codex／Claude Token 用量監控

- 狀態：approved / Phase 1 contract + Codex and Claude local ledger ingestion +
  source-side export gate + cross-device merge + account-aware reports implemented
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
- `evals/schemas/claude-usage-projection.schema.json`
- `evals/schemas/usage-export-policy.schema.json`
- `evals/schemas/usage-export-batch.schema.json`
- `evals/schemas/usage-merge-state.schema.json`
- `evals/schemas/usage-identity-diagnostic.schema.json`
- `evals/schemas/usage-report.schema.json`

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

## Claude local ledger

Claude importer 接受一份已從本機 Claude Code session transcript
（`~/.claude/projects/<project>/<session-id>.jsonl`）萃取出的單一 completed-turn
projection：每筆 assistant 訊息記錄含 `message.usage`（`input_tokens`、
`cache_creation_input_tokens`、`cache_read_input_tokens`、`output_tokens`、
`output_tokens_details.thinking_tokens`）、`message.model`、`sessionId` 與訊息
`uuid`。萃取步驟只允許複製這些 metadata 欄位到 projection，不得複製 `content`、
`thinking` 區塊文字或任何 tool 輸入輸出。

Importer 只讀已存在的本機 JSON，不啟動 `claude` CLI、不讀取 transcript 全文，也不進行
網路呼叫。每個 `session_id + turn_id`（採用該筆訊息的 `uuid`）會產生確定性的事件 ID；
相同內容重播不重複寫入，同一 ID 若出現不同內容則 fail closed。Ledger 與 Codex 共用同一套
`UsageLedger.psm1` 寫入器，但各自使用獨立檔案：

- `.local/usage/claude-ledger.jsonl`：不含 email 與對話內容的 raw usage ledger。

匯入範例：

```powershell
pwsh -NoProfile -File scripts/claude-usage-import.ps1 `
  -ProjectionPath .local/capture/claude-turn.json `
  -AccountReadPath .local/capture/claude-account-read.json
```

`AccountReadPath` 指向的檔案是 `{ auth: <claude auth status --json 原始輸出>,
environmentState: { apiBilling, thirdParty } }`；identity 規則與判定與現有
`claude-switch-account` Skill 完全一致（見上方 Identity rules），只有 identity 為
`verified` 時才會寫入。目前沒有 Claude 官方 quota/rate-limit window 的對等本機
snapshot（Claude Code 未提供對應的本機可讀 API），此範圍留待未來需求出現再評估。

## Source-side export gate

在任何摘要離開來源電腦之前，`scripts/usage-export-run.ps1` 套用確定性的欄位
allowlist、跨事件彙總與政策閘門，將 `.local/usage/*.jsonl` 裡已驗證的事件轉成一份
可匯出的 de-identified 批次；無法通過任一道檢查的批次一律進 quarantine，不得匯出。

- 政策檔 `.local/governance/usage-export-policy.json`（Git-ignored）必須明確
  `export_allowed: true` 才允許產生可匯出批次；缺檔或 `false` 都視為 local-only，
  這是預設值，不是例外狀況。
- 匯出批次（`evals/schemas/usage-export-batch.schema.json`）只允許
  `alias`、`provider`、`model`、token 加總、`estimated_cost_usd`、`run_count`、
  `period` 與 `schema_version`／`policy_version`／`redaction_version`／
  `source_version`；`additionalProperties: false` 逐層鎖死，account_id、
  device_id、email、session_id、turn_id 一律不得出現。
- 彙總以 `alias + provider + model` 為分組鍵，同一分組內只加總「有值」的
  metric；整組都沒有值才標記 `unavailable`，不得填 0。
- 進入批次前逐筆事件必須是 `verification_status: verified`（`Read-ProjectDUsageLedgerEvents`
  在讀取階段已強制），否則整批次 fail closed 並寫入 quarantine 紀錄
  （只含 `quarantined_at` 與不可回推原始值的 `reason`，不含被拒內容本身）。
- 最終序列化的批次文字還會過一次 `Get-ProjectDUsageExportCanaryPatterns`
  內容掃描（email、憑證樣式字串、本機路徑、`github.com`／`.git` 等 repository
  URL 樣式）。這一層存在的理由是：`model` 欄位的字元集刻意允許 `.`、`/`、`:`
  以支援真實模型版本字串，這代表理論上可以塞入形似 repository URL 的值並仍通過
  schema pattern；content canary 掃描能在這種情況下攔下來。

## Cross-device merge

`scripts/usage-merge-run.ps1` 把來自不同裝置、已通過 export gate 的批次
（`.local/usage/export/usage-export-*.json`，由操作者手動搬運到目標裝置，例如
複製到 `.local/usage/import/`）合併成單一 `.local/usage/merge/merge-state.json`
累加狀態，供後續報表（#43）讀取。工作與家用電腦**不會**共用或同步原始 ledger
或這份合併狀態檔本身——每台裝置各自的 raw ledger 永遠留在原地，只有已經過 #41
去識別化與 allowlist 過濾的批次會被搬動。

- **重播安全**：每個批次以其正規化 JSON 內容算出 `sha256` digest；同一 digest
  出現第二次時回報 `replayed`，累計數字不變。
- **device 可分辨**：延續 #41 新增的 `device_id`／`environment` 欄位，合併時以
  `alias + provider + model + device_id + environment` 為分組鍵——同一帳號
  （`alias` 相同）在工作與家用電腦的用量可以放進同一份報表查詢，但不會被悄悄
  相加成單一裝置的數字。
- **政策已在來源端擋過**：合併工具只接受能通過 `usage-export-batch.schema.json`
  驗證的批次；未過 #41 政策閘門的批次一開始就不會被匯出，這裡只是再次驗證
  schema 作為第二道防線，不合規的輸入會回報 `rejected` 且不影響既有累計值。
- **離線與亂序安全**：累加只做加法且以 digest 去重，不論輸入順序或分批到達
  順序為何，最終 totals 都一樣（見 contract test 的 order-independence 案例）；
  程序中斷重啟只需要重新指向同一份 `merge-state.json`，不會遺失或重算已合併批次。
- **UTC**：批次與合併狀態全程使用 UTC ISO 8601 時間戳；報表時區轉換與 Provider
  官方 quota reset 邊界的對應留待 #43 處理，本層不假設任何特定時區。

## Account-aware reports

`scripts/usage-report-run.ps1` produces a deterministic daily／weekly report,
in one of two modes:

- `-Mode local`：直接讀本機 ledger（`.local/usage/codex-ledger.jsonl`／
  `claude-ledger.jsonl`），依 `day`／`week` 切 bucket，再依
  provider／`alias`（帳號）／`device_id`／`environment`／`model` 分組。
- `-Mode merged`：讀 `.local/usage/merge/merge-state.json` 的累加結果——
  由於 #42 的 totals 已經保留每個匯出批次的 `period`，只要操作者固定用同一種
  granularity（例如每天跑一次 export）產生批次，合併後仍能維持日期切分。

兩種模式都輸出相同的 `evals/schemas/usage-report.schema.json` 形狀：
`rows`（token 加總、estimated cost、runs，Provider 未提供的欄位固定
`unavailable`，不用 0 或猜測值頂替）與 `quota_snapshots`（原樣帶入既有的
`codex-quota-snapshot.json`，跟 `rows` 的本機 token 診斷完全分開呈現，兩者
永遠不會被合併成同一個指標）分屬報表的兩個獨立區塊。

`warnings` 陣列涵蓋四種型別：

- `unknown_identity`／`account_mismatch`：來自 `codex-usage-import.ps1`／
  `claude-usage-import.ps1` 在識別失敗時新寫入的
  `.local/usage/diagnostics/identity-events.jsonl`（新增的
  `Write-ProjectDUsageIdentityDiagnostic`，只在 identity 非 `verified` 時
  才落地一筆不含 email／account_id／alias 的紀錄，import 本身仍照舊 fail
  closed、不寫入 ledger）。
- `data_gap`：在請求的期間內，任何一個 day／week bucket 完全沒有資料列，就
  視為資料缺口並列出。
- `anomalous_usage`：呼叫端可用 `-BaselineInputTokensPerRun`／
  `-BaselineOutputTokensPerRun`／`-BaselineCostPerRun` 提供一個明確、確定性
  的「每次 run」門檻；沒有提供門檻就不會產生任何 anomaly 警告——基準值永遠
  由操作者明確給定，不是模型推論或統計學習出來的。

報表產出後一樣會過內容 canary 掃描（沿用 `UsageExportGate` 的
`Test-ProjectDUsageExportContentSafe`），逐項比對驗收條件：不揭露 email、
organization、repository、path、prompt、session ID；相同輸入重跑會得到完全
一致的 rows 與 warnings（`generated_at` 除外）；整條流程不呼叫模型或對外
連線。

## Verification

```powershell
pwsh -NoProfile -File scripts/tests/usage-contract.contract.ps1
pwsh -NoProfile -File scripts/tests/codex-usage-ledger.contract.ps1
pwsh -NoProfile -File scripts/tests/claude-usage-ledger.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-export-gate.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-merge.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-report.contract.ps1
pwsh -NoProfile -File scripts/tests/claude-switch-account.contract.ps1
pwsh -NoProfile -File scripts/projectd-check.ps1 -SkipFleet -SkipGlobal -SkipWiring
```

Claude 帳號 Status 的穩定公開入口是：

```powershell
pwsh -NoProfile -File scripts/claude-account.ps1 -Action Status
```

此入口只委派到 canonical `claude-switch-account` Skill，不複製驗證邏輯。

## Current boundary

目前已建立 contract、Codex／Claude completed-turn 本機 ingestion seam、來源端
export gate，與跨裝置合併累加器，但尚不修改使用者層級的 Codex OTel 設定、不自動從
Claude transcript 萃取 projection、不啟動 Codex App Server、collector 或報表，也不會
自動排程執行 `usage-export-run.ps1`／`usage-merge-run.ps1`（一律由操作者手動觸發，且
批次從來源裝置搬到合併裝置這一步也由操作者手動完成，工具本身不做任何跨裝置傳輸）。
Live capture（含自動萃取 Claude projection 的步驟）與 rollout 留在 #44；後續 tickets
必須沿用本契約，且所有 raw ledger、匯出批次／quarantine 紀錄與合併狀態仍只保存在
Git-ignored 的本機資料區。

## References

- [Codex App Server account endpoints](https://learn.chatgpt.com/docs/app-server)
- [Codex observability and telemetry](https://learn.chatgpt.com/docs/config-file/config-advanced)
- [Claude Code monitoring usage](https://code.claude.com/docs/en/monitoring-usage)
- [Claude Code costs and usage](https://code.claude.com/docs/en/costs)
- [Identity and event contract ticket #38](https://github.com/OliverMingHao1024/projectD-core/issues/38)
