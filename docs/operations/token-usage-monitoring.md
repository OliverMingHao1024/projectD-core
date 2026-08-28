# Codex／Claude Token 用量監控 — 操作手冊

本頁是操作指南；行為契約與驗收條件見
[`docs/specs/token-usage-monitoring.md`](../specs/token-usage-monitoring.md)。

## 資料位置

全部在 `ProjectRoot/.local/` 之下，整個 `.local/` 已在 `.gitignore` 排除，永遠不進版控：

| 路徑 | 內容 |
|---|---|
| `.local/governance/usage-device.json` | 本機裝置檔（`device_id`、`environment`）。每台電腦各自獨立，不得跨電腦複製。 |
| `.local/governance/usage-account-profiles.json` | 私人帳號對照檔（`account_id`、`alias`、`email`）。同一帳號在工作與家用電腦必須用同一筆資料。 |
| `.local/governance/usage-export-policy.json` | 匯出政策（`export_allowed`）。缺檔或 `false` 都代表 local-only。 |
| `.local/capture/*.json` | 已消毒的 collector 輸入（Codex completed-turn projection、`account/read` 結果）。 |
| `.local/usage/codex-ledger.jsonl`／`claude-ledger.jsonl` | 各 Provider 的本機 per-turn token ledger。 |
| `.local/usage/codex-quota-snapshot.json` | Codex 官方 quota/rate-limit window，與上面的 token ledger 分開存放。 |
| `.local/usage/diagnostics/identity-events.jsonl` | identity 解析為 `unknown`／`mismatch` 時的非識別化診斷紀錄。 |
| `.local/usage/export/usage-export-*.json` | 已去識別化、可匯出的批次（只有 `export_allowed:true` 才會產生）。 |
| `.local/usage/export/quarantine/*.json` | 被拒絕匯出的批次留下的隔離紀錄（只含原因，不含內容）。 |
| `.local/usage/merge/merge-state.json` | 跨裝置合併後的累加狀態。 |
| `.local/usage/reports/usage-report-*.json` | 產出的報表。 |

## 快速開始

```powershell
# 1. 在每台要監控的電腦上先套用本機接線（建立 device profile／預設政策）
pwsh -File scripts/usage-monitoring-rollout.ps1 -Mode Apply -Environment work
pwsh -File scripts/usage-monitoring-rollout.ps1 -Mode Apply -Environment home -AllowExport

# 2. 檢查目前狀態（唯讀）
pwsh -File scripts/usage-monitoring-rollout.ps1 -Mode Check

# 3. 手動編輯 .local/governance/usage-account-profiles.json，填入真實 account_id／alias／email
#    （account_id 用 New-ProjectDUsageIdentifier -Kind Account 產生一次即可，之後每台電腦沿用同一筆）

# 4a. Claude：自動掃描本機 session transcript 並匯入（不需要手動準備 capture 檔）
pwsh -File scripts/claude-usage-collect.ps1
#     只想抓最近的，避免第一次全量掃描太慢：
pwsh -File scripts/claude-usage-collect.ps1 -Since (Get-Date).AddHours(-2).ToString('o')

# 4b. Codex：目前仍需先手動準備 .local/capture/codex-turn.json 與 codex-account-read.json，
#     再匯入（Codex 本機用量資料的自動擷取方式尚待研究，見 #52 的後續票）
pwsh -File scripts/codex-usage-import.ps1 `
  -ProjectionPath .local/capture/codex-turn.json `
  -AccountReadPath .local/capture/codex-account-read.json

# 5. 只在明確允許匯出的電腦上，把本機 ledger 收斂成去識別化批次
pwsh -File scripts/usage-export-run.ps1 -PeriodStart 2026-08-01T00:00:00Z -PeriodEnd 2026-08-02T00:00:00Z

# 6. 手動把批次檔搬到要做跨裝置分析的位置（例如複製到另一台電腦的 .local/usage/import/），再合併
pwsh -File scripts/usage-merge-run.ps1 -BatchPath .local/usage/import/<搬過來的批次>.json

# 7. 產生報表（單機用 -Mode local，跨裝置彙整用 -Mode merged）
pwsh -File scripts/usage-report-run.ps1 -Mode local -GroupBy day `
  -PeriodStart 2026-08-01T00:00:00Z -PeriodEnd 2026-08-02T00:00:00Z
```

## 停用與移除

```powershell
# 停用匯出（可逆，不刪資料，工作電腦本來就該長期維持這個狀態）
pwsh -File scripts/usage-monitoring-rollout.ps1 -Mode Disable

# 徹底刪除這台電腦上所有本機用量資料與設定檔（不可逆，需要明確 -Confirm）
pwsh -File scripts/usage-monitoring-rollout.ps1 -Mode Remove -Confirm
```

`Disable`／`Remove` 都只影響 `.local/usage/` 與 `.local/governance/usage-*.json`，不會觸碰
`AGENTS.md`、`CLAUDE.md`、`vault/` 或任何其他 session-init 內容——這套監控從未注入這些檔案，
啟用或停用都不會改變 agent 每次 session 讀到的東西。

## 隱私邊界

- **永不匯出**：email、organization、project、repository、branch、path、remote URL、
  prompt、response、tool 輸入輸出、session/turn ID、任何憑證。這些欄位在 schema 層
  就用 `additionalProperties: false` 鎖死，匯出批次與報表都無法承載。
- **只在本機**：`.local/governance/usage-account-profiles.json` 的 email 只用來源端比對，
  絕不進入 ledger、批次或報表。
- **工作電腦預設 local-only**：沒有明確 `export_allowed: true`，任何匯出嘗試都會直接
  fail closed 並進 quarantine，不會產生可外傳檔案。
- **家用電腦才選擇性開啟跨裝置彙整**：`-Mode Apply -AllowExport`（或手動把
  `usage-export-policy.json` 的 `export_allowed` 設成 `true`）。

## Estimated cost 限制

`estimated_cost_usd` 這個欄位即使有值，也只代表 Provider／collector 自己回報的估算，
**不是帳單、不是官方 quota**。目前的 Codex／Claude importer 都沒有從 Provider 拿到
per-turn cost 欄位，因此這個欄位在 Phase 1 一律是 `unavailable`，不會用 0 或用固定
每 token 價格去猜。要看真正的計費／配額，一律以下列官方入口為準，不要用本報表：

- Codex：`account/rateLimits/read`（quota window）、`account/usage/read`（帳號層級用量），
  已由 `scripts/codex-quota-import.ps1` 存成獨立的 `codex-quota-snapshot.json`。
- Claude：`claude-account.ps1 -Action Status` 或官方帳單頁面。

## 疑難排解

| 現象 | 原因 | 處理 |
|---|---|---|
| import 直接失敗，訊息像是「identity is unavailable」 | `account/read` 回傳的 email 在本機 `usage-account-profiles.json` 找不到對應帳號 | 檢查 email 是否打錯、帳號是否還沒登記；`.local/usage/diagnostics/identity-events.jsonl` 會留一筆不含 email 的診斷紀錄 |
| `usage-export-run.ps1` 丟出「not allowed by local policy」 | 這台電腦的 `usage-export-policy.json` 缺檔或 `export_allowed:false` | 如果是工作電腦，這是預期行為（維持 local-only）；如果是想開放的家用電腦，用 `-Mode Apply -AllowExport` 或手動改政策檔 |
| `usage-export-run.ps1` 產生了 quarantine 紀錄 | policy 拒絕、identity 未驗證，或內容 canary 掃描命中 | 讀 `.local/usage/export/quarantine/*.json` 的 `reason` 欄位（只含原因，不含被拒內容），依原因排查 |
| 報表出現 `data_gap` 警告 | 該天／週在請求的期間內完全沒有任何一列資料 | 確認當天有沒有真的呼叫過 Codex／Claude、有沒有忘記跑 import |
| 報表出現 `unknown_identity`／`account_mismatch` 警告 | 對應期間有 import 因 identity 解析失敗而被拒絕 | 對照 `identity-events.jsonl` 的時間與 provider，處理帳號設定問題 |
| 想知道跨裝置彙整後某個帳號在兩台電腦各花多少 | 報表的 `rows` 本來就依 `device_id`／`environment` 分開列，不會悄悄合成一個數字 | 直接依 `device_id`／`environment` 篩選 `rows` |
| `claude-usage-collect.ps1` 第一次跑很慢 | 每次匯入都會重新驗證整份既有 ledger（跟 `claude-usage-import.ps1` 單筆匯入同樣的成本），歷史 transcript 累積的訊息一多，第一次全量掃描就是 O(n²) | 用 `-Since` 限定只掃最近的訊息；之後固定週期（例如每次 session 結束）跑一次，每次只有少量新訊息，就不會再慢 |

## 驗證

```powershell
pwsh -File scripts/tests/usage-monitoring-rollout.contract.ps1
pwsh -File scripts/tests/claude-usage-collect.contract.ps1
pwsh -File scripts/projectd-check.ps1 -SkipFleet -SkipGlobal -SkipWiring
```
