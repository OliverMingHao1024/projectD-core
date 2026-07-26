---
description: 發現 GitHub 高星 Claude Skill、篩選、把候選落 staging、留痕決策紀錄；不自動收錄。
argument-hint: "[關鍵字/技術棧] [--stars N] [--updated-within Nm] [--limit N]"
allowed-tools: ["Bash", "WebSearch", "Read", "Grep", "Glob", "Write", "Edit", "Task"]
---

# /skill-scout — GitHub Skill 發現與把關流程

你正在執行一個「發現 → 篩選 → staging → 留痕」的可重複流程。你**只做到產候選摘要、
落 staging、留痕**；「好不好用、要不要收錄」是使用者的主觀決定，你不得自行收錄或改動
正式 `packs/`。收錄（畢業）是使用者確認後的獨立動作。

## 參數解析

`$ARGUMENTS` 可能包含：
- 第一個非旗標詞：關鍵字或技術棧（例：`csharp`、`testing`、`agent`）。**未提供時**走預設
  掃描主題集（見下）。
- `--stars N`：star 門檻，預設 `>=200`。
- `--updated-within Nm`：最近 N 個月有 push，預設 `12m`。
- `--limit N`：每條查詢的候選上限，預設 `30`。

預設掃描主題集（無關鍵字時）：
`claude-code`、`claude-skill`、`claude-skills`、`agent-skills`、`ai-agent-skills`、
`awesome-claude`，並加一輪 code search `filename:SKILL.md`。

## 步驟 0：前置檢查（gh 可用性與登入）

先確認環境，未過關就停下來提示使用者，不要硬跑：

    gh --version
    gh auth status

- `gh` 未安裝 → 告知使用者需先安裝 GitHub CLI，中止本次流程。
- `gh auth status` 顯示未登入 → 提示使用者先執行 `gh auth login`（code search 與
  license API 都需要認證），中止本次流程。
- 通過才進入步驟 1。

> 注意：以下 gh 欄位能力為未實測的技術判斷，若某個 `--json` 欄位報錯，改用
> `gh api` 逐 repo 補齊（見步驟 4）。

## 步驟 1：用 gh 拉結構化候選（廣掃 + 精掃雙軌）

**廣掃（topic / 關鍵字 repo search）**，套用 star 門檻、排序、上限：

    gh search repos "claude skill SKILL.md" \
      --json fullName,stargazersCount,pushedAt,license,url,description,isArchived \
      --sort stars --order desc --limit 30

    gh search repos --topic claude-code --stars ">=200" \
      --sort stars --order desc --limit 30 \
      --json fullName,stargazersCount,pushedAt,license,url,isArchived

對預設主題集逐一查詢（或把使用者給的關鍵字帶入）。star 門檻、limit、topic 依參數覆寫。

**精掃（code search 找真的含 SKILL.md 的 repo）**：

    gh search code --filename SKILL.md "name description" --limit 30

code search 需登入且 rate limit 較嚴；若回 429／rate limit，等候或縮小 limit 重試，並在
摘要中標註「code search 未完整」。

**過濾**：丟掉 `isArchived=true` 者；丟掉 `pushedAt` 超過 `--updated-within` 窗（預設 12 個月）者。

## 步驟 2：WebSearch 補質化來源，交叉比對

用 WebSearch 找質化推薦，補 gh 結構化資料看不到的「口碑」盲點：

- 查詢範例：`awesome claude code skills`、`best claude SKILL.md repositories 2026`、
  `claude agent skills recommended`。
- 把 awesome-list、部落格點名的 repo 與步驟 1 的清單交叉比對：
  - 兩邊都出現 → 可信度加分。
  - 只在 WebSearch 出現、gh 沒撈到 → 補進候選池（記發現管道 = WebSearch/awesome-list 名稱）。
  - 只在 gh 出現、口碑無提及 → 保留，但在摘要標「僅 star，無質化背書」。

## 步驟 3：讀 skill-candidates.md，去重並帶出已拒絕清單

讀 `vault/governance/skill-candidates.md`：

- **已收錄**（`## 已收錄` 區塊）：從本次候選池中剔除，不重複評估。
- **已拒絕・暫緩**（`## 已拒絕・暫緩` 區塊）：**不要**自動剔除。把每筆的 `id`、`結論`、
  `理由`、上次`評估日期`一併列給使用者，讓使用者決定是否複審（不做到期自動重評）。
- 用每筆的 `- id：<owner>-<repo>` 當比對 key（等同 repo 的 `fullName` 轉小寫、`/` 換 `-`）。

## 步驟 4：對每個新候選做授權二次確認（硬門檻）

**不可只信步驟 1 的 `license` 欄**（GitHub 授權偵測是 best-effort，常為 null 或 `other`）。
對每個進入候選的 repo 做二次確認：

    gh api repos/{owner}/{repo}/license --jq '.license.spdx_id'

判定規則：
- 回 `MIT` / `Apache-2.0` / `BSD-3-Clause` 等明確 SPDX id → 標「授權明確」，可進 staging。
- 回 `null`、`NOASSERTION`、`other`，或 API 404 → 標「授權未明 → 不可收錄」。仍可列入摘要供
  使用者知情，但**不得**進入 staging，也不得畢業。

備用（一次補齊多欄位）：

    gh api repos/{owner}/{repo} \
      --jq '{stars:.stargazers_count, pushed:.pushed_at, license:.license.spdx_id, archived:.archived}'

## 步驟 5：產出候選摘要給使用者

以表格或條列輸出，每筆至少含：`來源名稱(owner/repo)`、`star 數`、`最近更新`、`授權
(SPDX)`、`發現管道`、`初步判斷`。分兩組呈現：
1. **本次新候選**（授權明確者優先，授權未明者標紅字附註）。
2. **既有已拒絕・暫緩清單**（附 id + 上次理由，供使用者決定是否複審）。

然後**停下來問使用者**：要試哪些候選？（不要自作主張全部落 staging。）

## 步驟 6：使用者選定的候選 → 落 packs/_staging/

對每個使用者選定、且授權明確的候選：

1. 建目錄 `packs/_staging/<owner>-<repo>/`（`<owner>-<repo>` 全小寫，與 candidates 的
   `id` 一致）。
2. 取回其 `SKILL.md`（及必要輔助檔）放進該子目錄。可用：

        gh api repos/{owner}/{repo}/contents/SKILL.md --jq '.content' | base64 -d

   或 clone 到暫存再挑檔。取回時記下當下的 commit hash：

        gh api repos/{owner}/{repo}/commits --jq '.[0].sha' -X GET -f per_page=1

3. 在該子目錄寫 `SOURCE.md`（欄位範本見 `packs/_staging/README.md`），填來源 URL、SPDX
   授權、擷取日期、commit hash、star 快照。

## 步驟 7：派 pg 對 staging 內容做乾跑把關

用 Task 工具派 `pg` sub-agent（pg 具 Bash）對本次落地的每個 `packs/_staging/<id>/` 做乾跑
（dry-run）基本把關，回報三類問題：
- **格式**：`SKILL.md` frontmatter 是否合法、必要欄位是否齊全。
- **過時**：內容是否引用已淘汰的 API／指令／版本。
- **矛盾**：是否與現有 pack 或憲法規則衝突。

pg 只回報、不改內容也不做收錄決定。把 pg 的乾跑結果原樣轉呈給使用者。

## 步驟 8：使用者主觀判斷收錄與否（你不自行決定）

把 pg 乾跑結果 + 你的觀察交給使用者，由使用者拍板。收錄**不是全有全無**——來源常混雜可用
原則與不適用的部分（依賴未擷取的其他 skill、與現有規則衝突的步驟、過度特化的範例等），
預設應評估是否只抽取其中可用片段，而非整包照搬：
- **整包收錄**：提示使用者這是獨立動作——需把內容改寫成跨工具通用表述、標注來源+授權後，
  移入 `packs/<stack>/`（新開 pack 需使用者確認命名，沿用小寫連字號慣例）。若屬「外部工具
  參考型」（本體在別處、只記何時用/怎麼裝），落點改為 `core/skills/`，frontmatter 用
  `type: external-tool-reference` + `source:`。判準：本體留在本 repo 維護 = pack；只引用外部
  = core/skills。
- **部分收錄**：只把使用者指認出的可用片段（原則、範例、檢查清單等）改寫進現有或新
  pack，其餘內容不帶入。仍需標注來源＋授權（整份來源的授權適用於抽取片段，抽取不免除
  授權標注義務）。在 `skill-candidates.md` 的「理由」欄寫清楚抽了什麼、捨了什麼、為何捨。
- **拒絕/暫緩**：清空該 `packs/_staging/<id>/` 目錄。

## 步驟 9：回填 skill-candidates.md（無論結果都要留痕）

對本輪每個經手來源，在 `skill-candidates.md` 追加或更新一筆：

- **寫入策略：區塊定位搬移，不整檔重寫**。用 `## 已收錄` / `## 評估中` /
  `## 已拒絕・暫緩` 三個 H2 錨點定位，只在對應區塊 append 或把既有筆從一區塊搬到另一區塊，
  絕不重排或改動使用者手改過的其他筆，避免破壞既有內容。
- 新候選還在等使用者判斷 → 放 `## 評估中`。
- 使用者判 `收錄` 或 `部分收錄` → 搬到 `## 已收錄`，補 `目標 pack`；若為 `部分收錄`，
  `結論` 寫 `部分收錄`，`理由` 必須寫清楚抽了什麼片段、捨了什麼、為何捨（供日後判斷是否
  值得回頭補收剩餘部分）。
- 使用者判 `拒絕`/`暫緩` → 搬到 `## 已拒絕・暫緩`，`理由` 必填。
- 每筆務必含 `- id：<owner>-<repo>`，與 staging 目錄名一致。

## 輸出

- 終端摘要：本次新候選清單 + 已拒絕清單（附理由）。
- 副作用：`packs/_staging/` 新增/清空、`skill-candidates.md` 更新。
- **絕不**自動改動正式 `packs/`；收錄是使用者確認後的獨立動作。
