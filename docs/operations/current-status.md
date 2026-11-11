# 目前狀態與邊界

本頁保存會隨時間變動的驗證狀態；Repository 首頁只連結到這裡。更新任何一項時，
一併寫上日期與證據來源。

- Governance Evals Phase 1–2 已完成。Phase 3 有 contracts、adapters、logs、hooks、gates
  與 bounded single-host 證據；live runner、observers、broader pilots、paired
  authorization、Copilot 與 cross-host matrix 尚未完成。
- Runtime Governance v2：2026-09-04 在 Codex 與 Claude 各完成一次 bounded single-host
  實機驗證（read 放行、授權後 workspace write 放行、未授權指令拒絕）。之後的唯讀分類
  放寬（2026-09-06 shell 唯讀清單與 dry-run、2026-10-20 `gh` 讀取、2026-11-06
  `codegraph` 查詢）改變了 policy digest，只有 contract 測試，尚未重新做實機驗證；
  當時「`git status` 被拒絕」的證據已不代表現行規則。
- Recovery、crash／reopen、observer 與其他模型／工具路徑尚未實機驗證。
- Copilot 尚未接上 `setup.ps1` 或 runtime hook。
- 本機 runtime state 外移到 `PROJECTD_STATE_HOME`／`PROJECTD_CACHE_HOME` 已核准設計，
  尚未實作（[規格](../specs/external-runtime-state.md)）。
- Pi runtime 不屬於 mandatory core，只能是 optional adapter。
