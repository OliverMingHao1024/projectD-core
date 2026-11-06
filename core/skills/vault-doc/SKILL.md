---
name: vault-doc
description: Create or update numbered Obsidian Vault issues, dev-logs, specs, and reports.
---

# Vault Doc

在專案的 Obsidian Vault 建立／更新文件，處理編號、必填欄位與 issue 生命週期。

## Step 1：確定 Vault 根目錄與前綴

| 專案 | Vault 根目錄 | 編號前綴 |
|------|-------------|---------|
| TBB | `D:\workspaces\Obsidian\OIiver\TBB` | `TBB` |
| 其他 | 依序查專案的 `AGENTS.md`、`CLAUDE.md`、`AI-INVENTORY.md` 的 Vault 路徑 | 依專案慣例 |

找不到 Vault 路徑時，先問使用者，不要自己猜一個位置。

## Step 2：取號（強制）

**編號跨所有文件類型共用同一序號。** 掃描以下五處，取最大 NNN 後遞增：

- `docs/issues/open/`
- `docs/issues/resolved/`
- `docs/dev-log/**/`
- `docs/specs/**/`
- `docs/lessons/**/`

檔名格式：`{prefix}-{YYYY}-{NNN:3}_{簡短描述}.md`（例：`TBB-2026-013_登入逾時未導回首頁.md`）

## Step 3：依文件類型建立

### Issue（新 Bug）→ `docs/issues/open/`

依 `docs/issues/ISSUE-TEMPLATE.md`，必填：**問題現象、重現步驟、影響範圍**；基本資訊表含建立日期、狀態 `open`、影響模組。

### Issue 結案 → 移至 `docs/issues/resolved/`

1. 補齊三個章節：**根本原因、修正方式、驗證結果**
2. 基本資訊表：狀態改 `resolved`、加「解決日期」
3. 在 `resolved/` 建立完整檔案並 read-back 後，依專案破壞性操作規則取得授權，再刪除 `open/` 原檔（等同搬移）
4. 相關 dev-log 以 `[[檔名]]` 互相連結

### Dev-log（功能完成／架構決策）→ `docs/dev-log/YYYYMM/`

必填：**需求來源、涉及模組（或子專案）、已完成、未完成/待驗證、修訂紀錄**（表格：日期｜說明）。架構決策另需：**決策內容、替代方案、選擇理由**。

### Spec → `docs/specs/YYYYMM/`

必填：**決策內容、替代方案、選擇理由**。

### 報告／交付文件（調查報告、分析報告等給客戶或內部的產出）

**任何產出的報告檔案（.docx／.pdf／.xlsx 等），一律連同一篇說明用 dev-log 一起歸檔，不得只留在暫存目錄或單獨交付。**

1. 依 Step 2 取號，判斷較符合 Issue（有明確問題現象/根因/修正）或 Dev-log（分析/調查/交付本身即為產出）；未牽涉程式碼修正、屬客戶問題調查者，預設歸類 Dev-log → `docs/dev-log/YYYYMM/`
2. 建立說明用 dev-log（依上方 Dev-log 必填欄位），內容需涵蓋：需求來源（誰提出、為何）、查核/分析方法、關鍵發現摘要、根因或結論、未完成/待驗證事項
3. 將原始報告檔案以同一編號檔名放入**同一資料夾**（例：`{prefix}-{YYYY}-{NNN}_標題.docx` 對應 `{prefix}-{YYYY}-{NNN}_標題.md`），dev-log 內「相關連結」註明該檔案名稱
4. 交付給客戶／使用者後，不得只在對話中留存或放在系統暫存路徑，需以此步驟歸檔後才視為完成

## 禁止事項

- ❌ 手動編輯 indexer 產生的檔案（例如 `_ai-context.md`）
- ❌ 跳號或各文件類型各自編號
- ❌ Issue 未補根本原因/修正方式/驗證結果就搬到 `resolved/`
- ❌ 相對日期（「昨天」「上週」）——一律寫絕對日期 YYYY-MM-DD

## 完成後

- 回報建立／更新的完整檔案路徑
- 若目前 agent 無 Vault 寫入權限，回報精確目標路徑並請求核准，不得改寫到其他位置

## Source

Moved from the retired `oai-core/shared-skills` into projectD. The `oai-core`
Vault row and the vault-ai indexer notes were dropped with that retirement.
