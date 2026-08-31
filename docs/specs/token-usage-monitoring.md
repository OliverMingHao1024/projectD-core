# Token Usage Monitoring

- 狀態：approved；contracts、Codex／Claude local collectors、export gate、cross-device merge、reports 與 opt-in rollout complete
- 完整採用與實作歷程：[projectD-knowledge archive](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/design/token-usage-monitoring-full-history.md)
- 操作手冊：[`docs/operations/token-usage-monitoring.md`](../operations/token-usage-monitoring.md)

## 目的與資料邊界

本功能提供帳號感知、裝置感知的本機 token／cost metadata 診斷。它不讀取或保存 prompt、response、
thinking、tool input/output、email、repository URL、完整路徑或 credential；不啟動模型、不修改
Codex OTel、不自動排程，也不自行跨裝置傳輸資料。

所有 raw ledgers、capture、quota snapshots、quarantine、merge state 與 reports 都位於 Git-ignored
的 `.local/`。來源電腦預設 local-only；只有明確政策允許且通過 export gate 的去識別化摘要才能離開。

## 身份與事件契約

- 帳號 profile 只保存 provider、操作者命名 alias 與穩定 account ID 的 digest，不保存 email。
- Import 前必須用本機 provider identity evidence 驗證帳號；unknown 或 mismatch 一律 fail closed，
  不寫入 ledger。
- Event ID 由 provider、session ID 與 turn ID 等 metadata 確定性產生；相同內容可安全重播，
  同 ID 不同內容視為衝突。
- Metrics 使用 `{ "status": "observed", "value": ... }` 或
  `{ "status": "unavailable", "value": null }`；provider 未提供的值不得填 0 或推估。
- Ledger 使用 single-writer lock 與同目錄 durable replacement，只能寫入
  `ProjectRoot/.local/usage/*.jsonl`。

Canonical metrics：input、cached input、output、reasoning、cache read／creation tokens，以及
estimated cost。估算成本不等於帳單或 quota。

## Local-only task attribution

事件可帶 `local_context.label`，Codex 取操作者命名的 thread name（否則 cwd basename），Claude 取
transcript cwd basename。此欄位只存在本機 ledger：export 與 merge 使用明確 allowlist，程式碼不讀取
該欄位；merged report 固定輸出 `null`。內容 canary 掃描報表時只遮蔽這個合法本機 label 的值。

## Collectors 與 ledgers

| Provider | Local source | Ledger | 身份邊界 |
|---|---|---|---|
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` 的 session／turn／token metadata | `.local/usage/codex-ledger.jsonl` | 需操作者準備一次已消毒的 `account/read` 結果。 |
| Claude | `~/.claude/projects/**/*.jsonl` 的 assistant usage metadata | `.local/usage/claude-ledger.jsonl` | 唯讀 `claude auth status --json` 或指定既有檔案。 |

- Collectors 只萃取 schema allowlist 欄位，不複製訊息內容、thinking 或 tool 資料。
- Codex 同一 turn 的多個 token snapshots 只匯入最後一筆；quota window 保存於獨立 snapshot，
  不與 per-turn ledger 混用。
- Claude 排除 sidechain 與無 usage 訊息；`captured_at` 使用原訊息 timestamp，確保重掃可重播。
- Importers 只讀已存在的本機 projection，不啟動 provider CLI 模型或對外連線。

## Export gate

`scripts/usage-export-run.ps1` 只有在 Git-ignored 的政策檔明確設定 `export_allowed: true` 時才產生
可匯出批次；缺檔或 false 都維持 local-only。

Export batch 只允許 alias、provider、model、device/environment、period、token／cost totals、run count
與 schema／policy／redaction／source versions。Account ID、email、session／turn ID、local context、路徑與
repository 資訊不得出現。Schema 使用 `additionalProperties: false`，序列化後再執行 email、credential、
path 與 repository URL canary 掃描；任一檢查失敗即 quarantine，且紀錄不包含被拒內容。

## Cross-device merge 與 reports

- `scripts/usage-merge-run.ps1` 只接受通過 export schema 的批次，以 canonical JSON SHA-256 去重。
- 分組鍵保留 alias、provider、model、device、environment 與 period；亂序或重播不改變最終 totals。
- 原始 ledgers 與 merge state 不同步；批次由操作者手動搬運。
- `scripts/usage-report-run.ps1` 支援 local 與 merged daily／weekly reports；quota snapshots 與 token rows
  分開呈現，不合併為同一指標。
- Warnings 僅包含 unknown identity、account mismatch、data gap，以及由操作者明確提供 baseline 才啟用的
  anomalous usage。相同輸入的 rows 與 warnings 必須 deterministic（`generated_at` 除外）。

## Canonical assets

- Schemas：`evals/schemas/usage-*.schema.json`、provider projection／quota schemas
- Core contract：`scripts/lib/UsageContract.psm1`
- Import／collect：`scripts/codex-usage-*.ps1`、`scripts/claude-usage-*.ps1`
- Export／merge／report：`scripts/usage-export-run.ps1`、`scripts/usage-merge-run.ps1`、
  `scripts/usage-report-run.ps1`
- Rollout：`scripts/usage-monitoring-rollout.ps1`

## 現行驗證

```powershell
pwsh -NoProfile -File scripts/tests/usage-contract.contract.ps1
pwsh -NoProfile -File scripts/tests/codex-usage-ledger.contract.ps1
pwsh -NoProfile -File scripts/tests/claude-usage-ledger.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-export-gate.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-merge.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-report.contract.ps1
pwsh -NoProfile -File scripts/tests/usage-monitoring-rollout.contract.ps1
pwsh -NoProfile -File scripts/tests/claude-usage-collect.contract.ps1
pwsh -NoProfile -File scripts/tests/codex-usage-collect.contract.ps1
pwsh -NoProfile -File scripts/projectd-check.ps1 -SkipFleet -SkipGlobal -SkipWiring
```

## 現行限制

- 不啟動 Codex App Server；Codex identity 仍需操作者準備 `account/read` projection。
- Claude Code 沒有對等的本機 quota window API。
- 不自動排程 collectors／export／merge／report，也不自動傳輸批次。
- 所有 provider 未提供的 metrics 維持 `unavailable`。
