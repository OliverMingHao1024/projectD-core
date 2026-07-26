---
project: projectD-core
date: 2026-07-27
type: architecture
status: accepted
evidence_level: verified
technologies: [PowerShell, Python, SQLite, FTS5, FastEmbed]
commits: [e041d3f]
supersedes: []
verified_by:
  - "pytest: 16 passed"
  - "hybrid benchmark: 20/20 top-five hits"
  - "skill quick validation"
  - "PowerShell parser validation"
---

# 建立可攜式 local-first 專案歷程搜尋

## Context

[user-confirmed] 專案歷程搜尋需要搬到公司電腦使用，但公司環境可能限制對外網路，也不能把
個人專案內容、索引或模型 cache 一併帶入。工具與治理規則可以透過 Git 共用，
runtime 與資料則必須留在各自裝置。

## Symptom or goal

建立一套預設本機執行、可離線部署且明確限制資料範圍的 project history
runtime，並保留以下邊界：

- 所有 runtime、模型、allowlist、index 與 log 都放在被 Git 忽略的
  `.local/project-history/`。
- 只索引使用者明確加入 allowlist 的 repository。
- 缺少 Python、FastEmbed 或 embedding model 時，未取得下載同意就停止。
- 公司與個人裝置只共用工具及治理規則，不共用資料與衍生索引。

## Attempts

### accepted：獨立的本機 runtime 與明確 allowlist

以 `setup-project-history.ps1` 建立專用 `.venv`、模型 cache 與空白
allowlist；以 `project-history.ps1` 統一提供 `status`、`rebuild`、`update`
與 `query`。受限環境可改用 wheelhouse、內部 PyPI、核准的模型 cache 或
IT 管理的 Python。

### rejected：自動掃描整台電腦或自動加入 repository

這會讓公司資料範圍不透明，也可能把未核准 repository 納入索引。因此初始
allowlist 必須為空，且不加入 Git hook、背景監控或自動 filesystem scan。

### failed：底層 benchmark 使用 FastEmbed 預設 Temp cache

第一次直接呼叫 Python benchmark 時未傳入正式 model cache，FastEmbed
因此在 Windows Temp 建立另一份 cache 並嘗試下載模型。這條路線不符合
「下載前確認」與固定本機資料位置的規則，已明確否決。

處理方式：

- 刪除該次產生的 Temp cache。
- Python CLI 的 hybrid mode 改為必須提供 `--cache-dir` 或
  `FASTEMBED_CACHE_PATH`。
- 未明確傳入 `--allow-download` 時強制使用 offline mode。
- 加入測試，避免未設定 cache 時退回隱性下載。

## Root cause

FastEmbed 在未指定 cache 位置時會採用自己的預設 Temp cache；底層 CLI
原先也沒有 fail-closed 的下載邊界，因此直接繞過 wrapper 執行時仍可能觸發
網路存取。

## Resolution

正式採用可攜式 local-first runtime：

- 安裝、模型與資料全部位於 `.local/project-history/`。
- setup 與底層 CLI 都要求明確下載授權。
- 一般操作只透過統一 PowerShell wrapper。
- operation log 只保留 command、時間、耗時、成敗與 error type，最多七天
  與 10 MB；不記錄查詢文字、搜尋結果或專案內容。
- Git 只保存工具、空白 allowlist template 與治理說明。

## Verification

- Python tests：16 passed。
- Hybrid retrieval benchmark：20/20 題在 top five 命中。
- Skill quick validation：通過。
- PowerShell AST parser：兩個 scripts 均通過。
- 正式 index：成功索引並查詢兩個個人裝置上已核准的專案。
- Git ignore：`.local/project-history/index.db` 與 `projects.json` 均被排除。
- Log inspection：未發現查詢文字或 retrieved content。

## Applicability

適用於 Windows 上的 projectD-core、本機單人使用、受限公司網路，以及需要
明確資料隔離的 repository history retrieval。

不代表已具備多人共享、集中式權限管理、雲端同步或企業級 Vector Database
服務。若未來導入這些能力，需要重新評估資料分類、access control、稽核與
retention policy。
