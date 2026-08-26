# SA 技術分析：從 GitHub 引入高星 Skill 的可重複機制

> **歷史分析**：預設廣掃、repo 級 ID 與「外部參考型／pack」落點判準已被
> `../../docs/adr/0016-targeted-skill-intake.md` 取代；保留本檔供追溯。

對應 PRD：`vault/governance/prd-skill-import.md`
分析者：SA agent／日期：2026-07-24

## 0. 探勘結論摘要

讀了 PRD 全文、憲法（`core/constitution/rules.md`）、vault init 序列、三個現存 pack 的 `SKILL.md`、兩個 `core/skills/*.md`、四個 agent 定義，以及 `~/.claude/skills/` 下 grilling / grill-me 兩個實際 command/skill 檔。關鍵技術事實：

- **`core/commands/` 確實是空的**。專案內無任何 slash command 範例可抄。
- **關鍵約束（PRD 未點出）**：Claude Code 只會自動載入 `~/.claude/commands/`、`.claude/commands/`（專案級）或 plugin 目錄下的 command。放在 repo 的 `core/commands/skill-scout.md` **不會**自動變成可呼叫的 `/skill-scout`。本 repo 現行做法是「agents 複製到 `~/.claude/agents/`、packs 連結到 `~/.claude/skills/`」——command 也必須比照，複製或 symlink 到 `~/.claude/commands/skill-scout.md` 才能真正被呼叫。這點必須交給 SD 納入設計與交付步驟，否則驗收標準第 4 條「可被當作 slash command 呼叫」過不了。
- 三個現存 pack 都是**單一 `SKILL.md`（無子目錄）** 的扁平結構，frontmatter 只有 `name` + `description`。
- 兩個 `core/skills/*.md` 的 frontmatter 都帶 `type: external-tool-reference` + `source:`，是問題 5 的分類判準來源。

## 1. 開放問題逐項定案

### 問題 1：slash command 最終命名
**定案：維持 `/skill-scout`。** 語意精準——command 只做「發現→篩選→產候選摘要→落 staging→留痕」，不做收錄決定（收錄是使用者主觀判斷）。取名 `/skill-import` 會誤導使用者以為會自動匯入，與 PRD 第 5 節「command 本身不自動改動正式 packs」矛盾。檔案本體叫 `skill-scout.md`，真正被呼叫的名稱取決於它落在 `~/.claude/commands/` 的檔名，兩處要一致。

### 問題 2：`packs/_staging/` 目錄結構粒度 + 是否需要 README
**定案：一候選一子目錄（`packs/_staging/<candidate-name>/`）＋ 需要 `_staging/README.md`。**

一候選一子目錄優於扁平：外部 skill 常不只一個檔（`SKILL.md` 可能帶 `agents/*.yaml`、輔助 script），扁平放會檔名衝突。`<candidate-name>` 命名慣例：`<owner>-<repo>`，與 `skill-candidates.md` 的「來源名稱」欄一對一對應。每個候選子目錄內建議放 `SOURCE.md`：記來源 URL＋授權＋擷取日期＋原始 commit hash。

`_staging/README.md` 需要，說明：(a) 尚未畢業、不可視為正式規範；(b) 畢業條件（pg 乾跑通過＋使用者主觀確認）；(c) 畢業後移入 `packs/<stack>/`，拒絕則清空並在 `skill-candidates.md` 留痕；(d) `_staging/` 內容不應被其他 agent 當作可信 pack 載入。

### 問題 3：`skill-candidates.md` 格式
**定案：三區塊（收錄／評估中／拒絕・暫緩）＋ 每筆用「H3 標題 + 固定 key 條列」，不用寬表格。**

理由（agent 可解析性）：寬表格在長理由文字時容易撐爆換行破欄；H3 標題（`### owner/repo`）+ 固定前綴 key 條列（`- 授權條款：`、`- 結論：`、`- 理由：`）對 LLM 解析最穩，理由再長也不破格式。三區塊用固定 H2 錨點：`## 已收錄`、`## 評估中`、`## 已拒絕・暫緩`。`結論` 欄用固定 enum：`收錄`/`暫緩`/`拒絕`。

補充：每筆 H3 下加一行 `- id：<owner>-<repo>`，與 `_staging/` 子目錄名一致，讓「候選紀錄 ↔ staging 目錄 ↔ 目標 pack」三者用同一把 key 串起來。

給 SD：需定案「command 回填時的寫入策略」——建議區塊定位追加/搬移（append/move within section），避免整檔重寫破壞使用者手改內容。

### 問題 4：`gh` CLI 實際能力調查

> **未實測聲明**：分析當下無 Bash 可驗證 `gh` 是否安裝/登入。以下基於 `gh` CLI 已知穩定能力做技術判斷，SD/PG 實作前務必先跑 `gh --version` 與 `gh auth status` 落地驗證。

**能不能一次拉到 star/pushedAt/license？——能，用 `gh search repos --json`：**
```bash
gh search repos "claude skill SKILL.md" \
  --json fullName,stargazersCount,pushedAt,license,url,description,isArchived \
  --sort stars --order desc --limit 30

gh search repos --topic claude-code --stars ">=200" --sort stars --limit 30 \
  --json fullName,stargazersCount,pushedAt,license,url
```

**三個技術陷阱（SD 須設計繞過）：**
1. `license` 欄可能是 null 或 `other`（GitHub 授權偵測是 best-effort）。授權把關是硬性收錄門檻，不能只信 search 結果，需二次確認：
   ```bash
   gh api repos/{owner}/{repo}/license --jq '.license.spdx_id'
   ```
   仍測不到就標記「授權未明 → 不可收錄」。
2. `gh search repos` 不看檔案內容，找「含 SKILL.md 的 repo」需用 code search：
   ```bash
   gh search code --filename SKILL.md "name description" --limit 30
   ```
   需登入、有較嚴格 rate limit。發現策略應雙軌：topic/關鍵字 repo search（廣）＋ code search（精）＋ WebSearch 的 awesome-list 交叉。
3. 需要認證：command 前置應檢查 `gh auth status`，未登入提示使用者先 `gh auth login`。

**`gh api` 補充：**
```bash
gh api repos/{owner}/{repo} --jq '{stars:.stargazers_count, pushed:.pushed_at, license:.license.spdx_id, archived:.archived}'
```

**預設掃描參數建議：**
- 預設 topic/關鍵字集：`claude-code`、`claude-skill`、`agent-skills`、`claude-skills`、`ai-agent-skills`、`awesome-claude`，加 code search `filename:SKILL.md`
- 預設 star 門檻：`>=200`（star 只初篩、不自動收錄，寧鬆勿嚴）
- 預設時間窗：近 12 個月有 push，排除 `isArchived=true`
- 預設 `--limit 30`、`--sort stars`；全部可被 command 參數覆寫

### 問題 5：「外部工具參考型」skill 落點
**定案：確認 PRD 傾向正確——工具參考型入 `core/skills/`，技術棧規範型入 `packs/`。**

| 判準 | → `core/skills/` | → `packs/<stack>/` |
|---|---|---|
| 本質 | 引用外部工具/技能，本體在別處 | 規範內容本體在本 repo 維護 |
| frontmatter | `type: external-tool-reference` + `source:` | `name` + `description` |
| 綁不綁技術棧 | 跨語言、跨專案通用 | 綁定特定技術棧 |
| 維護方式 | 只記「何時用/怎麼用/怎麼裝」 | 內容自行維護、改寫成跨工具通用表述 |
| 是否要 pg 遵循 | 否（能力/工具指引） | 是（code 規範） |

判準核心一句話：**本體是否留在本 repo 維護——留下維護＝pack，只引用外部＝core/skills。**

邊界情形：有些高星 skill 是「內容型技能」而非「外部工具指引」，即使發現自 GitHub，也應改寫成本 repo 內容後入 `packs/`（可能需要非技術棧綁定的新 pack，如 `packs/testing/`）。

## 2. `core/commands/` slash command 檔案格式

專案內無範例，建議格式：
```markdown
---
description: Scout high-star GitHub Claude skills, filter, stage candidates, and log decisions.
argument-hint: "[keyword/stack] [--stars N] [--updated-within Nm]"
allowed-tools: ["Bash", "WebSearch", "Read", "Write", "Edit", "Grep", "Glob"]
---
```

**關鍵注意（給 SD）：**
1. `allowed-tools` 需含 `Bash`（跑 gh）與 `WebSearch`。目前 `sa`/`sd` 只有 Read/Grep/Glob，`pg` 才有 Bash——「誰來執行 command」需定案，建議由具 Bash+WebSearch 的主 agent 或 `pg` 執行。
2. **生效路徑**：`core/commands/skill-scout.md`（原始碼）要 symlink/複製到 `~/.claude/commands/skill-scout.md` 才可被呼叫，交付步驟必須包含這步。
3. Codex/Copilot 不吃 Claude Code 專屬 frontmatter/`$ARGUMENTS` 語法，但 command 本身屬 Claude Code 專屬產物可接受（跨工具重構已列 out-of-scope）。

## 3. PRD 第 3 節新增檔案清單技術可行性檢查

| 項目 | 可行性 | 補充 |
|---|---|---|
| `packs/_staging/` | 可行 | 內容須明確標記為不可當正式 pack 載入 |
| `packs/_staging/<candidate>/` | 可行、確認採用 | 命名 `<owner>-<repo>`，與 candidates id 對齊 |
| `packs/_staging/README.md` | 可行、確認需要 | 內容見問題 2 |
| `vault/governance/skill-candidates.md` | 可行 | 格式見問題 3 |
| `core/commands/skill-scout.md` | 可行但有隱藏步驟 | 需額外複製到 `~/.claude/commands/` 才生效 |
| `INDEX.md` 修改 | 可行 | 補指向 candidates + PRD 即可 |

**PRD 清單的遺漏/風險：**
1. 漏了 command 的「安裝/生效」交付物：`~/.claude/commands/skill-scout.md`（連結或複本）。
2. 漏了每候選的來源/授權標注落點（建議 `_staging/<candidate>/SOURCE.md`）。
3. `_staging/` 的「不可信任」隔離未明說，需在 README 明確排除 `_` 前綴目錄不被當正式 pack。
4. 「開新 pack」命名慣例需定案（見下）。

## 4. 受影響 packs 與新開 pack 命名慣例

受影響：新增 `packs/_staging/`；首輪收錄命中現有技術棧時才會動既有三 pack。新開 pack 沿用小寫連字號慣例：技術棧型用棧名（如 `go`、`rust`），跨棧內容型用主題名（如 `testing`、`agent-patterns`）。每個新 pack 至少含一個 `SKILL.md`，frontmatter 用 `name` + `description`。開新 pack 需使用者確認。

## 5. 交棒給 SD

1. 命名定案：command = `/skill-scout`，檔 = `core/commands/skill-scout.md`。
2. 必須設計 command 的生效路徑：`core/commands/skill-scout.md`（原始碼）→ symlink/複製到 `~/.claude/commands/skill-scout.md`（生效），列入交付物。
3. 執行者指派：command 需 Bash+WebSearch，需明確指派由具工具的主 agent 或 pg 執行。
4. staging 結構：一候選一子目錄 + `SOURCE.md`；加 `packs/_staging/README.md`。
5. `skill-candidates.md` 格式契約：固定 H2 區塊 + H3 條列 + `id:` 錨點；需定案讀取/回填（區塊定位搬移，非整檔重寫）策略。
6. gh 契約（未實測，需 PG 落地驗證）：見問題 4 全部細節，含 license 二次確認、code search 找 SKILL.md、`gh auth status` 前置檢查、預設參數。
7. 分類判準：外部工具參考型 → `core/skills/`；規範內容本體 → `packs/`。
8. PRD 清單需補：command 生效檔、每候選 SOURCE 標注檔、`_staging/` 不可信任隔離。
