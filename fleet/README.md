# Fleet — 多專案共用 projectD-core

`fleet/fleet.json` 是本機專案清單（不進版本控制）。每個清單內的專案都透過
`AGENTS.md`、`CLAUDE.md`、`GEMINI.md` 的受管標記區塊連回 projectD-core，
既有入口內容不會被覆寫。Fleet 也只把該專案指定的 packs 接到
`.agents/skills/` 與 `.claude/skills/`，並在根目錄 `.gitignore` 維護精確路徑；
既有 Skills 與 ignore 內容會保留。

## 接線與檢查

```powershell
# 安全預檢：只讀 fleet.json 與三個明確入口路徑，不讀專案原始碼或 .gitignore
pwsh -File scripts/fleet-inspect.ps1

# 新增或更新 Fleet 入口、scoped pack junction 與 .gitignore 區塊
pwsh -File scripts/fleet-governance.ps1 -Mode Apply

# 唯讀驗證：缺檔、區塊漂移、無效 category／pack 均回傳失敗
pwsh -File scripts/fleet-governance.ps1 -Mode Check
```

真實的專案清單含個人路徑，不進版本控制，見 `fleet.json.example` 的格式，
自行複製一份 `fleet.json`（已在 `.gitignore` 排除）。

入口受管區塊只保存啟動路由，不複製憲法與治理正文；`.gitignore` 受管區塊包含
三個入口與每個 managed pack junction 的精確路徑，不會忽略整個 project-owned Skill
目錄。規則更新後所有專案下次 session 都會讀到同一份 core。若 core 無法解析，
入口會要求 AI 明確回報並停止修改，不得靜默略過。

Git ignore 規則不會自動取消追蹤已納入版本控制的檔案；既有 tracked 入口檔需由各 repo
另行明確處理。

新增、移除或調整 Fleet 項目後先執行 `Apply`，再用 `Check` 驗證。工具可安全重複執行；
若同一入口出現重複受管區塊，會停止並要求人工檢查，不自動刪除內容。
Fleet 與全域 setup/remove 共用相同的 managed-block inspect、plan、apply 與
rollback lifecycle；本機 state 存在 `.local/`，不會提交到 Git。

`fleet.json` 是唯一專案 allowlist，`packs` 必須明確填寫。Fleet 建立、預檢、接線與
驗證不得遞迴掃描 `D:\workspaces`、其他 workspace root、siblings 或清單內專案的
原始碼，也不得用跨 repo inline PowerShell 推測技術棧。若個別開發任務確實需要讀取
原始碼，必須在該單一 repository 的工作範圍內另行處理。

`fleet-inspect.ps1` 只驗證清單結構、專案目錄、canonical packs，並列出三個可能的
入口目標；它不建立或修改檔案。入口內容是否符合 desired state，仍由
`fleet-governance.ps1 -Mode Check` 負責。

## work / side 區分

每筆專案用 `category` 標記 `work`（公司/客戶工作專案）或 `side`（個人側專案），
理由：

- L0 與 L1–L6 路由可跨 work／side 使用；兩者都不強制跑完整角色流水線。
- `category: "side"` 通常使用 L0、必要 pack 與直接實作路由；遇到架構、安全或
  跨模組問題時，仍可按需使用 SA／SD。
- `category: "work"` 可依任務規模選用完整治理能力與 PM／SA／UX／SD／PG／QA 角色，
  但需求明確的低風險小任務仍可直接處理。
- 這只是清單裡的標記，目前沒有自動化行為依賴它——之後如果真的需要「只列出
  work 專案」之類的查詢，再依實際需求加工具，不預先假設。
