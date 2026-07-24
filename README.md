# projectD-core

從零設計、獨立維護的個人 AI 治理核心，不依賴外部 plugin。架構為 core + packs：
`core/` 是每個專案都共用的部分，`packs/` 是依專案技術棧選用的技能包。

## 目錄導覽

| 路徑 | 用途 |
|------|------|
| `CLAUDE.md` | session 啟動協議 |
| `core/constitution/rules.md` | L0 憲法 |
| `core/agents/` | PM / SA / SD / PG 四個角色 agent |
| `core/commands/` | slash command（目前為空，等實際需求出現再加）|
| `vault/` | 跨 session 記憶（身份、決策、制度路由、踩坑紀錄）|
| `packs/` | 依技術棧選用的技能包，目前：csharp、frontend-react-angular、python |
| `fleet/` | 多專案共用本 repo 的說明與清單範例 |
| `scripts/` | 全域安裝／移機與 Fleet 治理檢查腳本 |

## 使用方式

一個專案要用 projectD-core，就在該專案裡引用 `core/` 加上該專案技術棧對應的
`packs/`。Fleet 專案以受管入口區塊接線，細節見 `fleet/README.md`。

## 全域安裝／移機

`scripts/setup.ps1`（或雙擊 `scripts/setup.bat`）把本 repo 接進
`~/.claude/`，讓任何專案都能直接叫到 PM/SA/SD/PG 與各 pack：

- 設定 `PROJECTD_CORE` 環境變數指向本 repo
- 複製 `core/agents/{pm,sa,sd,pg}.md` 到 `~/.claude/agents/`
  （改了 agent 內容要重跑腳本才會反映）
- 用 junction 把 `packs/*` 連到 `~/.claude/skills/`（即時反映，不用重跑）
- 在 `~/.claude/CLAUDE.md` 寫入/更新 `PROJECTD_CORE_START/END` 標記區塊，
  說明 session 啟動時的讀取順序

**移機到新裝置**：把整個 `projectD-core` 資料夾複製或 `git clone` 到任意路徑，
執行 `scripts/setup.bat`（或 `pwsh -File scripts/setup.ps1`）即可，不需要手動
改任何路徑。腳本會自動定位自己所在位置。

**移除全域接線**：`scripts/uninstall.ps1`（或 `scripts/uninstall.bat`），
repo 本身不會被刪除。

## 設計原則

- 內容依實際使用累積，不預先假設涵蓋不到的情境
- 不依賴外部 plugin；需要時再個別評估引入，不整包依賴
- 每個 pack 只服務一個技術棧，不強迫所有專案共用所有技能
- L0 憲法常駐，L1–L6 只保留短路由並依任務語意按需載入
- PM／SA／SD／PG 是可選能力，不強迫低風險小任務跑完整流水線
- 行為變更與 bug 修復在條件允許時優先採 Red → Green → Refactor；
  無測試基礎設施的專案使用最小回歸驗證，不為形式擅自加依賴
