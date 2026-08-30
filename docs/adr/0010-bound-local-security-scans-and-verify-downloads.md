---
status: accepted
date: 2026-07-29
domain: supply-chain-security
---

# Bound local security scans and verify downloaded artifacts

projectD-core 的本機檢查只列舉明確允許的來源目錄與文字檔案類型，並在遞迴前排除快取、依賴、staging 與版本控制資料。Python 套件及 embedding model 必須依受控來源與固定 hash 驗證；內部套件來源仍可使用，但限 HTTPS、不得內嵌憑證，且不能繞過 hash lock。這項決策以較高的 allowlist 維護成本，換取較小的檔案存取邊界、可追溯的供應鏈完整性，以及較低的防毒行為誤判風險。

## Consequences

新增正式來源目錄、檔案類型、套件版本或模型 revision 時，必須同步更新相應 allowlist 或 manifest。驗證失敗一律停止，不自動降低 Defender、PowerShell 或下載完整性保護。
