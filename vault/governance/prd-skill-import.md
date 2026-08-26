# PRD：從 GitHub 引入高星 Skill 的可重複機制

> **歷史 PRD**：現行定向搜尋、路徑級候選、registry 與更新檢查架構見
> `../../docs/adr/0016-targeted-skill-intake.md`。本檔不再是現行行為契約。

> 本文件經 `/grill-me` 逐項確認決策後，由 `pm` agent 整理成正式 PRD。

## 1. 目標與動機

**目標**：為 `projectD-core` 建立一套「發現 → 篩選 → 試用把關 → 收錄」的可重複流程，把 GitHub 上高星、實際好用的 Claude Code Skill（`SKILL.md` 生態）有紀律地引進本 repo 的 `packs/`，並把方法沉澱成可重複呼叫的 slash command 與決策紀錄。

**動機**：
- 目前 `packs/` 內容全部靠自己從零累積，缺乏系統性吸收外部成熟 skill 的管道。
- 一次性抄一個 skill 無法規模化；需要一套可重複、留痕、避免重複評估的機制。
- 使用者同時使用 Claude Code、Codex、GitHub Copilot 三種 agent 工具，收錄內容需寫成跨工具通用、不綁死單一工具語法。

**非目標（動機層面的界線）**：本次不追求「一次把所有好 skill 搬完」，而是先跑通「一輪完整流程 + 把流程工具化」。

## 2. 範圍（Scope）

### In-scope
- **SKILL 來源定義**：以 Claude Code Skill 生態（`SKILL.md` 格式）為候選來源；但收錄後的內容須改寫成跨工具通用的表述，不倚賴 Claude Code 專屬語法。
- **技術棧範圍**：不限於現有 packs（csharp、frontend-core、frontend-react、frontend-angular、typescript / node-runtime、python）；發現高星且好用者可開新 pack。（使用者已知悉此與憲法第 4 條「不預先假設」的精神張力並選擇開放，本 PRD 不再質疑。）
- **搜尋與篩選**：以 `gh` CLI 拉結構化資料（star 數、最近更新、關鍵字排序）快速縮小候選；以 WebSearch 找質化推薦（awesome-list、部落格）交叉比對。star 只用於初篩，不作為自動收錄依據。
- **授權把關**：只收錄具明確開源授權（MIT/Apache/BSD 等）者；每份納入檔案標注來源連結與授權條款。
- **staging 流程**：新增 `packs/_staging/` 暫存候選，`pg` 做一次乾跑（dry-run）格式／過時／矛盾的基本把關。
- **收錄判斷**：最終「好不好用」由使用者主觀決定；畢業後才移出 `_staging/` 進正式 pack。
- **決策紀錄**：新增 `vault/governance/skill-candidates.md` 記錄每個評估過的來源（含被拒絕者），並在 `INDEX.md` 補索引。
- **工具化**：把方法沉澱成 `core/commands/` 底下一個可重複呼叫的 slash command。
- **首輪執行**：跑一輪完整流程（搜尋 → 篩選 → staging → 收錄）作為機制的驗證與範例。

### Out-of-scope（明確排除）
- **不修改** `core/constitution/rules.md`（憲法保持精簡，本 SOP 只放 `vault/governance/`）。
- **不處理 pack 內部格式的跨工具重構**：Codex／Copilot 具體怎麼讀 pack 內容、pack 內部格式如何拆分共用，留待之後另開一輪規劃。
- **不做自動排程／cron／到期自動重評**：slash command 為手動觸發；被拒絕候選無自動重評期限。
- **不搬動治理記憶到 Obsidian**：PRD 與決策記錄維持放 `vault/governance/`；Obsidian（`D:\workspaces\Obsidian`）是給其他專案技術文檔用的獨立系統，兩者不合併。
- 本次不承諾收錄任何特定數量或特定 skill；收錄與否以流程結果為準。

## 3. 新增的目錄與檔案清單

| 類型 | 路徑 | 說明 | 狀態 |
|------|------|------|------|
| 目錄 | `packs\_staging\` | 候選暫存區，與正式 pack 同層，底線前綴區隔未畢業狀態 | 新增 |
| 目錄（建議）| `packs\_staging\<candidate-name>\` | 每個候選一個子目錄，內含其 `SKILL.md` 與來源／授權標注 | 新增（SA 評估） |
| 檔案（建議）| `packs\_staging\README.md` | 說明 staging 用途、畢業條件、與正式 pack 的關係 | 新增（建議）|
| 檔案 | `vault\governance\skill-candidates.md` | 決策紀錄；每個評估過的來源一筆（含拒絕者）| 新增 |
| 檔案 | `core\commands\skill-scout.md`（暫定命名）| 可重複呼叫的 slash command 定義 | 新增 |
| 檔案 | `vault\governance\prd-skill-import.md` | 本 PRD | 新增（本檔）|
| 修改 | `vault\governance\INDEX.md` | 補索引指向 `skill-candidates.md` 與本 PRD | 修改 |

**畢業（graduation）狀態轉移**：
`候選出現 → 進 packs/_staging/ → pg 乾跑基本把關 → 使用者主觀判斷 → 收錄則移入 packs/<stack>/（新開或既有 pack），拒絕/暫緩則留紀錄並清出 staging`。

## 4. `skill-candidates.md` 欄位格式建議

分「已收錄／評估中／已拒絕・暫緩」三區塊，方便 slash command 每次重跑時把「已拒絕」清單連同上次理由一併列出供使用者複審。每筆候選欄位：

| 欄位 | 必填 | 說明 |
|------|------|------|
| 來源名稱 | 是 | repo 名或 skill 名 |
| 來源連結 | 是 | GitHub URL（或 awesome-list／文章來源）|
| 授權條款 | 是 | MIT / Apache-2.0 / BSD 等；無明確授權者不得收錄 |
| star 數（評估時） | 是 | 初篩時的快照數值 |
| 最近更新 | 是 | 評估時該來源的最後 commit／release 日期 |
| 評估日期 | 是 | 本次評估日 |
| 結論 | 是 | `收錄` / `暫緩` / `拒絕` 三選一 |
| 理由 | 是 | 結論的簡短依據（尤其拒絕／暫緩必填，供日後複審）|
| 目標 pack | 收錄時填 | 收錄後落在哪個 pack（含新開 pack 名）|
| 發現管道 | 建議 | `gh` / WebSearch / awesome-list 名稱，供交叉比對追溯 |

**格式範例（單筆）**：

```markdown
### example/skill-repo
- 來源連結：https://github.com/example/skill-repo
- 授權條款：MIT
- star 數（評估時）：1.2k
- 最近更新：2026-06-30
- 評估日期：2026-07-24
- 結論：收錄
- 理由：實際試用有效，格式清晰，授權明確
- 目標 pack：packs/xxx
- 發現管道：gh search + awesome-claude-code
```

## 5. Slash command 的輸入／輸出行為

**性質**：手動觸發、可重複呼叫；不做排程。

**輸入（參數，最終由 SD 定案）**：
- 可選關鍵字／技術棧（例：`csharp`、`testing`、`agent`），無參數時走預設掃描主題集。
- 可選 star 門檻與時間窗（例：近 N 個月有更新）作為初篩參數，有合理預設值。

**執行步驟**：
1. 用 `gh search repos` / `gh api` 依關鍵字＋star＋最近更新拉候選結構化清單。
2. 用 WebSearch 找質化推薦（awesome-list、部落格），與步驟 1 交叉比對，補彼此盲點。
3. 讀取 `skill-candidates.md`，排除已收錄者，並列出既有「已拒絕」清單附上次拒絕理由供使用者決定是否複審。
4. 對每個新候選檢查授權；無明確開源授權者直接標記不可收錄。
5. 產出候選摘要（來源／star／授權／更新日／初步判斷）給使用者。
6. 使用者選定要試的候選 → 內容進 `packs/_staging/`。
7. 提示由 `pg` 對 staging 內容做乾跑（格式正確性、明顯過時／矛盾）基本把關。
8. 使用者主觀決定收錄與否；收錄則改寫為跨工具通用表述、標注來源＋授權、移入正式 pack；未收錄則清出 staging。
9. 無論結果，於 `skill-candidates.md` 追加／更新該來源紀錄（含結論與理由）。

**輸出**：
- 終端摘要：本次新候選清單 + 已拒絕清單（附理由）。
- 副作用產物：`packs/_staging/` 新增內容（暫存）、`skill-candidates.md` 更新。
- command 本身不自動改動正式 `packs/`；收錄（畢業）是使用者確認後的獨立動作。

**角色分工對應**：搜尋／篩選／紀錄可由執行 command 的 agent 完成；乾跑把關明確歸 `pg`；收錄與否的主觀判斷歸使用者（呼應憲法第 2 條角色分工）。

## 6. 驗收標準（Acceptance Criteria）

**結構產物**
1. `packs/_staging/` 目錄存在，且與正式 pack 同層、以底線前綴區隔。
2. `vault/governance/skill-candidates.md` 存在，含第 4 節欄位，且分「收錄／評估中／拒絕・暫緩」三態。
3. `vault/governance/INDEX.md` 新增索引指向 `skill-candidates.md`（與本 PRD）。
4. `core/commands/skill-scout.md`（或最終定名）存在且可被當作 slash command 呼叫。

**流程可執行性**
5. 執行該 slash command 能：用 `gh` 拉出結構化候選、用 WebSearch 補質化來源、交叉比對後產出候選摘要。
6. 重跑該 command 時，會排除已收錄者，並列出既有「已拒絕」清單附上次理由（不做日期到期自動判斷）。
7. 任一候選進 `packs/_staging/` 後，`pg` 能對其做一次乾跑把關並回報格式／過時／矛盾問題。

**授權與留痕**
8. 任何最終收錄進正式 pack 的檔案，皆標明來源連結與明確開源授權；無授權者一律不得收錄。
9. 每個被評估過的來源（含被拒絕者）在 `skill-candidates.md` 都有一筆含結論與理由的紀錄。

**首輪執行**
10. 完成至少一輪完整流程（搜尋 → 篩選 → staging → 使用者判斷），且該輪所有經手來源均已留痕於 `skill-candidates.md`（收錄數量可為 0，只要流程走通且留痕即算通過）。

**界線遵守**
11. `core/constitution/rules.md` 未被本次工作修改。
12. 未觸及 pack 內部格式的跨工具重構（Codex／Copilot 讀取方式）——確認留待後續。
13. 治理記憶未搬遷至 Obsidian；`vault/governance/` 維持為唯一治理記錄本體。

## 7. 開放問題（交 SA／使用者釐清，不阻擋交棒）

1. slash command 最終命名（暫定 `/skill-scout`）。
2. `packs/_staging/` 內每個候選的目錄結構粒度（一候選一子目錄 vs. 扁平），以及是否需要 `_staging/README.md`。
3. `skill-candidates.md` 用條列或表格（影響 command 每次讀取／回填的解析難度）。
4. `gh` 預設掃描的主題關鍵字集與 star／更新時間門檻預設值。
5. 收錄「外部工具參考型」skill（如 `/grill-me` 那類）時，落點是 `packs/` 還是既有的 `core/skills/`——本 PRD 傾向：工具參考型入 `core/skills/`，技術棧規範型入 `packs/`，由 SA 確認。

## 交棒（Handoff to SA）

本 PRD 基於使用者已拍板的決策，將其轉為可執行規格，範圍界線（第 2 節）明確對應決策界線。請 `sa` 據此進行技術分析：
- 探勘 `gh` CLI 可用性與 `gh search repos`／`gh api` 的實際欄位（star、pushedAt、license）能否一次滿足初篩需求；
- 決定 `skill-candidates.md` 的可解析格式與 command 讀寫策略；
- 判定 slash command 在 `core/commands/` 的定義方式與參數契約；
- 確認第 7 節開放問題並回填；
- 界定哪些 packs 受影響、是否需要新開 pack 的命名慣例。
