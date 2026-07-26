# projectD-core architecture deepening

## Goal

依序深化 Project History Record Lifecycle、LocalHistoryRuntime 與
GovernanceWiring。每階段必須維持可執行、可測試、可獨立回退。

## Phase 1 — Project History Record Lifecycle

- `HistoryCandidate` 只存在 `.local`，不得進 Git 或正式 index。
- `HistoryRecord` 只有在人工確認「保留」後才建立，並可進 Git。
- `HistoryProjection` 可重建，不是事實來源。
- `CandidateDisposition` 只在本機記錄 fingerprint、結果與時間，不保存內容。
- 保留流程依序為：驗證 Candidate、建立 Record、驗證可索引、刪除 Candidate。
- 任一步驟失敗不得留下半套 Record，也不得刪除 Candidate。
- 排除後刪除 Candidate 內容並寫入本機 Disposition。
- 主要 test seam 是 retain/defer/exclude 的完整 workflow，不直接依賴 raw dict。

## Phase 2 — LocalHistoryRuntime

- PowerShell Bootstrap 只負責 Python、venv、套件、模型與下載同意。
- Python Runtime module 擁有路徑、allowlist、mode、index、query 與狀態規則。
- PowerShell command 只作 Windows adapter。
- 預設 mode 為 `hybrid`；`lexical` 必須明確設定，禁止靜默降級。
- `status` 與 query output 必須顯示 active mode。
- Runtime 管理 `project list/add/remove`；不自動掃描 filesystem。
- `rebuild/update` 先建立並驗證暫存 index，成功後才原子替換正式 index。
- 失敗時保留舊 index。
- 保留既有 `status/rebuild/update/query` 與 setup flags。
- 既有本機 config 自動遷移；index 可重建。

## Phase 3 — GovernanceWiring

- 單一 desired state 描述 managed entry blocks、skill junction、agent/command
  ownership 與 `PROJECTD_CORE` environment 設定。
- setup、fleet check/apply 與 uninstall/remove 共用 inspect、plan、apply/remove
  lifecycle。
- mutation 前完成 conflict 與 ownership preflight。
- mutation 後重新 inspect。
- 中途失敗只回滾本次修改且確認 owned 的項目。
- 非 owned 檔案、junction 與 environment value 不得修改。
- 主要 test seam 是暫存環境中的 inspect → plan → apply/remove → inspect，
  包含 marker 損壞、duplicate block、ownership conflict 與 rollback。

## Delivery

- 順序固定為 Record Lifecycle → LocalHistoryRuntime → GovernanceWiring。
- 每階段使用 red → green TDD，完成 focused tests 與相關 full suite。
- 每階段獨立 commit。
- 最後分別依 repository standards 與本 spec 審查差異，再推送 Git。
