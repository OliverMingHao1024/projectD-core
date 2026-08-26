# 計畫：從 GitHub 引入高星 Skill 的可重複機制

> **歷史計畫**：其中的預設廣掃、repo 級候選 ID、落點分類與單一 Claude command 架構，
> 已由 `../../docs/adr/0016-targeted-skill-intake.md` 取代。現行入口是
> `../../core/skills/skill-scout/SKILL.md`、`skill-registry.json` 與獨立
> `skill-update-check`；本檔保留最初決策脈絡。

> 本檔是 skill-import 機制的總計畫，彙整 PM/SA/SD 三份文件的決策與目前執行狀態。
> 詳細內容見各自文件，本檔只做「現在到哪、下一步做什麼」的單一入口。

## 背景與目標

`projectD-core`（`core/` + `packs/` 架構）目前 `packs/` 內容全靠自己從零累積。本計畫建立
一套有紀律的「發現 → 篩選 → 試用把關 → 收錄」流程，把 GitHub 上高星、實際好用的 Claude
Code Skill（`SKILL.md` 生態）引進來，內容改寫成跨工具通用（因為使用者同時用 Claude
Code、Codex、GitHub Copilot），並把方法沉澱成可重複呼叫的 `/skill-scout` slash command。

## 決策依據（經 /grill-me 逐項確認）

| # | 決策點 | 結論 |
|---|--------|------|
| 1 | SKILL 定義 | Claude Code Skill 生態來源，內容須寫成跨工具通用（pack 格式本身怎麼拆分給 Codex/Copilot，本次不處理）|
| 2 | 技術棧範圍 | 不限現有三個 pack，發現高星好用者可開新 pack |
| 3 | 篩選標準 | star 數初篩 + 必須實際試用才收錄，非自動搬入 |
| 4 | 授權要求 | 嚴格：只收錄明確開源授權（MIT/Apache/BSD 等），標明來源與授權 |
| 5 | staging 機制 | `packs/_staging/` 暫存，`pg` 乾跑把關，使用者主觀判斷是否畢業 |
| 6 | 決策記錄 | `vault/governance/skill-candidates.md` 記錄所有評估過的來源（含拒絕者），避免重複評估 |
| 7 | 執行方式 | 先跑一輪完整流程，同時把方法做成可重跑的 `/skill-scout` slash command（非自動排程）|
| 8 | 搜尋工具 | `gh` CLI（結構化：star/更新時間/授權）+ WebSearch（質化推薦）交叉比對 |
| 9 | 範圍界線 | 不修改 `core/constitution/rules.md`；不處理 pack 跨工具格式重構；治理記錄不搬去 Obsidian |
| 10 | 拒絕候選重評 | 不設自動到期，每次重跑 command 都列出「已拒絕」清單附理由，由使用者決定要不要複審 |

完整脈絡見：[prd-skill-import.md](prd-skill-import.md)

## 技術定案（SA）

- command 命名 `/skill-scout`；檔案本體 `core/commands/skill-scout.md` **必須複製**到
  `~/.claude/commands/` 才會生效（Claude Code 只自動載入 `~/.claude/commands/`）。
- `gh search repos --json` 可一次拉 star/更新時間，但 `license` 欄常為 null，需
  `gh api repos/{o}/{r}/license` 二次確認；找「含 SKILL.md 的 repo」需用
  `gh search code --filename SKILL.md`（需登入、有 rate limit）。
- 分類判準：外部工具參考型（本體在別處，只記何時用/怎麼裝）→ `core/skills/`；
  技術棧規範型（內容本體自行維護）→ `packs/`。

完整脈絡見：[sa-analysis-skill-import.md](sa-analysis-skill-import.md)

## 架構設計（SD）

- 三個產物用同一把 key `<owner>-<repo>` 串起：`skill-candidates.md` 的 `id` 欄 ↔
  `packs/_staging/<owner>-<repo>/` 目錄名 ↔ 畢業後的目標 pack。
- 執行者：`/skill-scout` 由**主 session** 執行（互動式，需與使用者來回確認）；只有第 7
  步「乾跑把關」用 Task 派給 `pg`（非互動、一次性）。
- command 生效方式比照現有 agents，用 `Copy-Item -Force`（Windows junction 不支援單檔），
  補進 `scripts/setup.ps1`（冪等安裝）而非只手動跑一次。

## 執行狀態

### 已完成

- [x] PRD（`prd-skill-import.md`）
- [x] SA 技術分析（`sa-analysis-skill-import.md`）
- [x] SD 架構設計（本檔未另存 SD 逐字稿，設計內容已落實為下列檔案）
- [x] `core/commands/skill-scout.md`
- [x] `packs/_staging/README.md`（含 `SOURCE.md` 欄位範本）
- [x] `vault/governance/skill-candidates.md`（骨架，三區塊皆空）
- [x] `vault/governance/INDEX.md` 補索引
- [x] `scripts/setup.ps1` — 新增 Step 3 複製 command；packs junction 排除 `_` 開頭目錄
- [x] `scripts/uninstall.ps1` — 對應補上移除 `skill-scout.md`

### 待辦

- [x] 執行 `pwsh -File scripts\setup.ps1`，把 `skill-scout.md` 接進 `~/.claude/commands/`
- [ ] 開新 session 確認 `/skill-scout` 出現在 command 清單（已啟動非互動 session，但因預算錯誤中止，尚未取得清單回應）
- [x] 跑第一輪 `/skill-scout`：
  - [x] 驗證 `gh --version` / `gh auth status` 前置檢查
  - [x] 驗證 `gh search repos --json` 欄位是否如預期（stargazersCount/pushedAt/license）
  - [x] 驗證 `gh api .../license` 二次確認邏輯能否正確過濾 null 授權
  - [x] 驗證 `gh search code --filename SKILL.md` 是否受 rate limit 影響
  - [x] 驗證 WebSearch 交叉比對是否補到 gh 遺漏的候選
- [x] 使用者選定候選 → 落 `packs/_staging/<id>/` + 寫 `SOURCE.md`（本輪暫緩後已清除 staging）
- [x] 派 `pg` 乾跑把關，回報格式/過時/矛盾問題
- [x] 使用者主觀判斷收錄與否 → 回填 `skill-candidates.md`（本輪結論為暫緩，收錄數為 0）
      只要流程走通且留痕）

## 明確排除（Out of scope）

- 不修改 `core/constitution/rules.md`
- 不處理 pack 內部格式的跨工具（Codex/Copilot）重構
- 不做自動排程／cron／到期自動重評
- 不將治理記憶搬遷至 Obsidian（`D:\workspaces\Obsidian` 是其他專案技術文檔用的獨立系統）
