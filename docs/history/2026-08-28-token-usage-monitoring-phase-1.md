---
project: projectD-core
date: 2026-08-28
type: feature
status: accepted
evidence_level: verified
technologies: [PowerShell, JSON Schema, GitHub Actions, GitHub Issues]
commits: [3b08c4f, 95f7d8d, eb5f77c, 9cae7f2, f531dfe, 0d1c595]
supersedes: []
verified_by:
  - "usage-contract.contract.ps1 passed"
  - "codex-usage-ledger.contract.ps1 passed"
  - "claude-usage-ledger.contract.ps1 passed"
  - "usage-export-gate.contract.ps1 passed"
  - "usage-merge.contract.ps1 passed"
  - "usage-report.contract.ps1 passed"
  - "usage-monitoring-rollout.contract.ps1 passed (end-to-end two-device fixture)"
  - "projectd-check -GovernanceEvals: 30/30 checks passed"
  - "6 PRs merged with CI (repository-governance + secret-scan) green: #45-#50"
---

# 完成 Codex／Claude Token 用量監控 Phase 1（#38–#44）

## Context

[verified] projectD-core 已有 `claude-switch-account` 這類單一帳號狀態檢查能力，
但沒有任何機制能回答「Codex 跟 Claude 各自實際花了多少 token、在哪台電腦、哪個帳號」，
也沒有跨裝置（工作／家用電腦）彙整用量、找出異常耗用來源的方式。

[user-confirmed] 使用者在另一個 session（以 branch 名稱 `codex/token-usage-monitoring`
留下、當時尚未 commit 的工作狀態）已核准了以 GitHub Issues #38–#44 表達的七步驟
roadmap；本次 session 發現該分支後，經使用者確認「依序處理」，逐張票接手完成剩餘
五張（#40–#44），並修正過程中發現的兩個上游票（#41、#42）規格缺口。

## Symptom or goal

在不新增任何模型呼叫、不污染 AGENTS／CLAUDE／session-init、不影響 Codex／Claude
host 可用性的前提下，建立一套 provider-neutral 的本機用量監控：能辨識帳號與裝置、
能在工作電腦維持 local-only、能在家用電腦選擇性開放去識別化的跨裝置彙整、能產出
每日／每週報表並標示異常。

## Decision

依序完成並合併 #38–#44 全部七張票：

1. **#38 契約**（PR #45）：`scripts/lib/UsageContract.psm1` + 6 份 JSON Schema，定義
   provider-neutral 的 account/device/usage-event 語意，identity 分 `verified`／
   `unknown`／`mismatch` 三態，billing source 分 `subscription`／`api-key`／
   `third-party-cloud`。
2. **#39 Codex ledger**（PR #45 同批）：`scripts/lib/UsageLedger.psm1` +
   `codex-usage-import.ps1`／`codex-quota-import.ps1`，single-writer、durable
   replacement、replay-safe 的 `.local/usage/codex-ledger.jsonl`。
3. **#40 Claude ledger**（PR #46）：`claude-usage-import.ps1`，資料來源是 Claude Code
   本機 session transcript（`~/.claude/projects/<project>/<session-id>.jsonl`）萃取
   出的 completed-turn projection，架構完全比照 Codex。
4. **#41 export gate**（PR #47）：`scripts/lib/UsageExportGate.psm1` +
   `usage-export-run.ps1`，來源端 allowlist／去識別化／政策閘門，未過閘門一律
   quarantine，不得匯出。
5. **#42 跨裝置合併**（PR #48）：`scripts/lib/UsageMerge.psm1` +
   `usage-merge-run.ps1`，以批次內容 SHA-256 digest 去重，累加只加總「有值」的
   metric。**同時擴充 #41 的匯出 batch schema**，補上 `device_id`／`environment`
   欄位——這兩個欄位原本不在 #41 的允許清單裡，但 #42「裝置可分辨」的驗收條件
   需要它們，且兩者都是不可回推真人身份的隨機值，判定為 #41 訂驗收條件時的疏漏
   而非刻意禁止，經使用者確認後補上。
6. **#43 報表**（PR #49）：`scripts/lib/UsageReport.psm1` +
   `usage-report-run.ps1`，`local`／`merged` 兩種模式，warnings 涵蓋
   `unknown_identity`／`account_mismatch`／`data_gap`／`anomalous_usage`。**再次
   擴充 #42 的 merge-state row key**，補上批次的 `period`，否則跨裝置模式會失去
   日期切分能力；同時在 #39／#40 的 import 腳本新增
   `Write-ProjectDUsageIdentityDiagnostic`，讓 identity 解析失敗時留下非識別化
   診斷紀錄，供報表讀取。
7. **#44 rollout**（PR #50）：`scripts/usage-monitoring-rollout.ps1`（Check／
   Apply／Disable／Remove）、雙裝置端到端 contract test，以及操作手冊
   `docs/operations/token-usage-monitoring.md`。

## Alternatives

### rejected：export batch 永久排除 device_id／environment

嚴格照 #41 原始驗收條件的允許清單，這兩個欄位不該出現在匯出批次裡。但沒有它們，
#42 的「裝置可分辨」需求無法實作。權衡後認定它們屬於隨機、不可回推身份的安全欄位，
擴充 #41 schema 比另外發明一套「合併時才附加裝置標籤」的旁路機制更一致、更好驗證。

### deferred：即時擷取 Claude transcript 或啟動 Codex collector

Phase 1 只建立「已存在的本機投影檔案 → ledger」這段 ingestion seam，不負責從
Claude transcript 自動萃取、也不啟動 Codex App Server 或 collector。理由與
Governance Evals v2 Phase 1 相同：先固定 provider-neutral 的資料契約，真正的 live
capture 留到有具體需求時再開新 ticket，避免在契約還沒穩定前就綁定特定 host 的
即時整合方式。

### deferred：cost estimate 用固定價格表推算

`estimated_cost_usd` 目前兩個 Provider 的 importer 都沒有拿到官方 per-turn 成本
欄位。沒有採用「查一份寫死的每 token 價格表去估算」的做法，因為那不是 Provider
自己回報的值，且價格會變動、需要維護；一律標記 `unavailable`，與「Provider 未提供
不得用 0 或猜測值」的既有原則一致。

## Resolution

[verified] #38–#44 全部完成並關閉，6 個 PR 合併：

- `evals/schemas/usage-*.schema.json`（9 份）：account profiles、device profile、
  usage events、Codex/Claude usage projection、Codex quota projection/snapshot、
  export policy/batch、merge state、identity diagnostic、report。
- `scripts/lib/{UsageContract,UsageLedger,UsageExportGate,UsageMerge,UsageReport}.psm1`。
- `scripts/{codex,claude}-usage-import.ps1`、`codex-quota-import.ps1`、
  `usage-export-run.ps1`、`usage-merge-run.ps1`、`usage-report-run.ps1`、
  `usage-monitoring-rollout.ps1`。
- `scripts/tests/{usage-contract,codex-usage-ledger,claude-usage-ledger,
  usage-export-gate,usage-merge,usage-report,usage-monitoring-rollout}.contract.ps1`，
  全部已接入 `projectd-check.ps1`。
- `docs/specs/token-usage-monitoring.md`（規格＋roadmap）、
  `docs/operations/token-usage-monitoring.md`（操作手冊）。
- `evals/governance-assets.json` 登錄全部新工具與 SHA-256 完整性指紋。

過程中額外修正一個潛藏的 PowerShell bug：`@($X)` 包一個被 `Where-Object` 篩到
零筆結果的變數，得到的是 `@($null)`（一個 null 元素），不是空陣列，導致
`usage-export-run.ps1`／`usage-report-run.ps1` 在無既有 ledger 檔案時對空字串路徑
丟出例外；已在取用處補上 `Where-Object { $_ }` 過濾修正。

## Verification

- 7 個新 contract test 全數通過（見 frontmatter `verified_by`）。
- `pwsh -File scripts/projectd-check.ps1 -GovernanceEvals`：30/30 checks passed。
- `pwsh -File scripts/tests/projectd-check.contract.ps1`：PROJECTD_CHECK_CONTRACT_OK。
- 6 個 PR（#45–#50）在 GitHub Actions 的 `repository-governance`／`secret-scan`
  皆為 green 才合併。
- 端到端雙裝置 fixture（`usage-monitoring-rollout.contract.ps1`）實際跑過完整
  capture → identity → redact → export → merge → report 鏈路，並靜態掃描確認
  沒有任何一支 usage-monitoring 腳本／模組觸碰 `AGENTS.md`／`CLAUDE.md`／`vault/`
  或呼叫模型／對外連線。

## Known limitations

- Live capture（自動從 Claude transcript 萃取 projection、啟動 Codex collector）
  尚未實作；目前必須由操作者手動準備 `.local/capture/*.json` 再呼叫 importer。
- `estimated_cost_usd` 在兩個 Provider 上都固定為 `unavailable`——沒有真正的
  per-turn 成本資料來源，不代表帳單或官方 quota。
- 批次從來源裝置搬到合併裝置這一步完全手動（複製檔案），沒有自動同步機制；
  這是刻意設計，避免引入額外的跨裝置傳輸管道與其攻擊面。
- `usage-account-profiles.json` 需要操作者手動建立並填入真實 `account_id`／
  `alias`／`email`，rollout 的 `Apply` 不會自動產生（schema 要求非空陣列，且
  account_id 必須跨裝置一致，不適合自動生成假資料）。
- 報表的 anomaly 偵測門檻完全由呼叫端手動提供，沒有任何統計學習或歷史基準推論。

## Applicability

此決策記錄涵蓋 projectD-core repository 內 Codex／Claude token 用量監控的完整
Phase 1（#38–#44）。它不代表已有自動化的 live capture、排程執行或跨裝置同步；
這些能力若日後有具體需求，應開新 ticket 並沿用本次建立的 provider-neutral
contract，而非重新設計資料格式。
