# 歷史研究：外部 LLM Wiki 與 projectD 受治理讀取

> **狀態：superseded as implementation authority / retained as research**
>
> 本檔保留 Karpathy LLM Wiki、第三方 repository、正確性與有效性驗證的研究證據，
> 不再作為實作權威。已核准的第一階段範圍位於
> [`docs/specs/external-knowledge-wiki.md`](../../docs/specs/external-knowledge-wiki.md)，
> 架構理由位於 ADR 0004–0009。以下舊提案若與 active spec 或 ADR 衝突，一律視為歷史
> 選項，不得據此實作。

## Superseded decisions

| 舊提案中的模糊或衝突 | 現行決策 |
|---|---|
| 同時做外部技術知識與 Feature Wiki | 第一階段只做 `intentype` System Feature Wiki |
| projectD-core 擁有具體 schema | KnowledgeWorkspace 擁有 schema、validator、fixtures 與 CI |
| `candidates/`、`reviews/`、`log.md` 共同保存狀態 | Candidate/review 只存在於 GitHub PR |
| `reviewed` 是頁面 lifecycle status | Review 是事件，不是可信狀態 |
| 只靠後續更新辨識過期 | Lint 持久偵測＋query RuntimeStale 防呆 |
| manifest 可依賴 workspace path | Committed manifest 只含 portable ID、commit、relative path 與 digest |
| 第一階段同時有 ingest/query/lint | 延後自動 ingest；先做 query/lint tracer bullet |
| 預留全文、hybrid 或向量搜尋 | 八頁 PoC 使用 deterministic lexical index |

本研究文件其餘章節保持原貌，用於追溯當時考量，不應再局部更新成第二份 active spec。

## 決策摘要

採用 Karpathy LLM Wiki 的架構概念，但不把 Wiki 內容放入 `projectD-core`：

- `projectD-core` 只維護治理、CanonicalSkill、workspace allowlist 與唯讀查詢介面。
- 原始來源留在各自專案或受控儲存區；外部 workspace 只保存來源 manifest、候選內容與
  經審核的 Markdown Wiki。
- LLM 產生內容一律先是 `candidate`，不得因生成成功、另一個 LLM 同意或格式正確而自動
  升格成正式事實。
- 正確性靠來源可追溯、deterministic gates、獨立檢查與風險相稱的人工 review；有效性
  則用固定問題集與現行 `query-project-history` baseline 比較。
- 第一階段只做本機／私有 Git 的小型 PoC；不導入背景掃描、hook、自動排程、向量資料庫
  或 MCP。

## 背景

Karpathy 的原始 LLM Wiki 是抽象設計模式，不是可直接安裝的產品或 Agent Skill。它把
知識系統分成 immutable raw sources、LLM-maintained wiki 與 schema 三層，並定義
`ingest`、`query`、`lint` 三項主要操作。查詢先讀內容索引，再深入相關頁面；操作時間線
則保存在 append-only log。

這個模式可以補足 projectD 目前「保存已驗證歷史」之外的需求：跨來源概念整理、比較、
矛盾標記與持續綜合。但它不能取代原始專案文件、Git、ADR、測試或
`query-project-history`，也不能讓 LLM 綜合頁面自動成為證據。

## 目標

1. 讓不同 AI Agent 能以同一個唯讀入口查詢外部知識 workspace。
2. 保存跨專案概念與綜合結果，同時可追溯至固定版本的原始來源。
3. 將生成、審核、升格、過期與取代做成明確生命周期。
4. 用可重跑 benchmark 判斷 Wiki 是否真的改善檢索與任務成果。
5. 保持 `projectD-core` 精簡，不增加 session-start context。

## 非目標

- 不把完整文件、PDF、聊天紀錄或秘密複製到 `projectD-core`。
- 不讓 Agent 自動掃描所有專案或未經選擇的使用者資料。
- 不以 Wiki 取代原始來源、正式 ADR、測試結果或 Git history。
- 不預設使用 Obsidian、特定 LLM provider、embedding、向量資料庫或 MCP。
- 不自動把每次 query 寫回 Wiki。
- 不因星數、展示效果或單次成功查詢直接進入正式使用。

## 目標架構

```text
專案文件 / Git / ADR / 測試 / 經選擇的外部來源
                         │
                         │ explicit export / exact source
                         ▼
                 source manifest layer
                         │
                         │ candidate ingest
                         ▼
                 external knowledge workspace
               ┌─────────┼─────────┐
               │         │         │
            candidates  wiki     index/log
               │         │
               └── review / lint ──┘
                         │
                         │ read-only adapter
                         ▼
                    projectD-core
                         │
                         ▼
                  Codex / Claude / 其他 Agent
```

### projectD-core 責任

- 定義 workspace registry、schema version 與允許的讀取根目錄。
- 維護跨 Agent CanonicalSkill：
  - `knowledge-query`：嚴格唯讀。
  - `knowledge-ingest`：指定來源、dry-run、候選輸出、明確升格。
  - `knowledge-lint`：預設唯讀報告；修復是另一個需授權動作。
- 路由 `query-project-history` 與 Knowledge Wiki 查詢，不混淆兩者證據地位。
- 對重要回答回讀 source manifest 指向的原始文件或 Git object。
- 不保存大量 Wiki 內容，也不在 session 初始化時預載外部 index。

### 外部 workspace 責任

建議使用獨立私有 Git repository：

```text
projectD-knowledge/
├─ purpose.md
├─ schema.md
├─ index.md
├─ log.md
├─ sources/
│  └─ manifests/
├─ wiki/
│  ├─ concepts/
│  ├─ entities/
│  ├─ systems/
│  ├─ comparisons/
│  └─ syntheses/
├─ candidates/
│  └─ <ingest-run-id>/
├─ reviews/
└─ scripts/
   └─ validate.*
```

- `sources/manifests/` 保存定位與 digest，不保存秘密或不必要的原始複本。
- `candidates/` 保存尚未確認的生成結果，正式 query 不得把它當成 verified evidence。
- `wiki/` 只接受通過 promotion gate 的頁面。
- `index.md` 是內容導航；`log.md` 只記 ingest、promotion、lint 與 schema migration，
  不強制記錄每次唯讀查詢。

## 資料契約

### Source manifest

```yaml
---
schema_version: 1
id: intentype-hotkey-design
source_type: git-file
repository: intentype
path: docs/adr/hotkey.md
commit: abc123
content_digest: sha256:...
captured_at: 2026-07-28
sensitivity: internal
---
```

必要條件：

- `id` 在 workspace 內唯一且穩定。
- Git 來源必須固定 commit；非 Git 來源必須有 content digest。
- manifest 必須能重新定位來源，否則只能保持 `candidate` 或標成 `stale`。
- 不記錄 Token、密碼、完整環境變數、未篩選 runtime log 或個資。

### Wiki page

```yaml
---
schema_version: 1
id: global-hotkey-design
type: concept
lifecycle_status: candidate
evidence_status: inferred
sources:
  - intentype-hotkey-design
last_verified: null
supersedes: []
superseded_by: []
---
```

頁面生命周期：

```text
candidate
  ├─ rejected
  └─ reviewed
       ├─ verified
       └─ needs-evidence

verified ── source drift / contradiction ──> stale
verified ── newer accepted page ───────────> superseded
```

- `candidate`：LLM 生成，尚未確認。
- `reviewed`：人已閱讀，但不代表每個主張都獲來源支持。
- `verified`：關鍵主張皆能回讀來源，且完成相稱的審核。
- `needs-evidence`：內容可能有價值，但證據不足。
- `stale`：來源 digest、版本或事實狀態已改變，需要重驗。
- `superseded`：保留歷史，但不是現行答案。
- `rejected`：不得出現在正式查詢答案中。

頁面狀態只能代表整體最低可信度。重要主張仍須在正文附近附 source ID、路徑或 commit
引用，不能只在 frontmatter 掛一串來源。

## 如何判斷 LLM 產生資料是否正確

### 正確性的操作定義

一項 LLM 產生內容只有同時滿足下列條件，才可標成 `verified`：

1. **來源忠實性**：關鍵主張能由所列來源直接支持，沒有把推論寫成原文事實。
2. **來源完整性**：來源存在、版本固定、digest 相符，且引用位置可回讀。
3. **時間有效性**：容易變動的主張有驗證日期；來源更新後自動降為 `stale`，不靜默沿用。
4. **矛盾可見性**：新舊來源衝突時保留雙方與適用範圍，不由 LLM 靜默選邊。
5. **證據分級正確**：`verified`、`user-confirmed`、`inferred`、`unknown` 不得互相冒充。
6. **審核獨立性**：生成者不能只靠自我檢查完成升格；至少需要 deterministic gate，
   高風險內容另需人類或領域 reviewer。

### 三層驗證

#### A. Deterministic gates

CI 或本機 validator 必須能重跑：

- YAML schema、必要欄位與 enum。
- source ID 存在、Git commit 可解析、digest 相符。
- Wiki link、index 登錄與唯一 page ID。
- 不允許 `verified` 頁面引用 `candidate`／`rejected` 當正式證據。
- 過期來源與被 supersede 頁面的狀態一致。
- 禁止 path traversal、越過 workspace allowlist 的 symlink／junction。
- 秘密與敏感資料掃描。
- 生成 diff 不得改動 raw source、schema 或 workspace 之外的路徑。

格式正確只能證明結構有效，不能證明內容為真。

#### B. LLM critique

可使用另一個隔離的 LLM pass 做輔助檢查：

- 將候選主張逐項對照來源，標示 supported、contradicted、not-found。
- 尋找跨頁重複概念與語意矛盾。
- 檢查摘要是否遺漏會改變結論的重要限制。
- 建議應補充的來源與人工判斷點。

LLM critique 只是 review evidence，不能單獨把頁面升成 `verified`。生成模型與 reviewer
模型即使不同，也可能共享相同偏誤或幻覺。

#### C. Human review

以下內容必須人工確認：

- 架構、安全、隱私、權限、部署與資料處理決策。
- 跨來源 synthesis、比較結論與推薦。
- 會影響 projectD 治理、Skill、角色或專案操作方式的頁面。
- 來源互相矛盾或需判斷適用範圍的內容。
- 首次建立的新 page type 或 schema migration。

Reviewer 應檢查來源與候選 diff，而不是只閱讀流暢的摘要。

## 如何判斷資料是否有效

「正確」是主張受證據支持；「有效」則是它確實改善使用者或 Agent 完成任務的結果。
兩者必須分開評估。

### 固定 benchmark

PoC 建立 10–20 個經人工審核的問題，至少包含：

- 精確事實查詢。
- 跨兩個以上來源的比較。
- 專案決策與被拒絕／superseded 方案辨識。
- 語意改寫查詢，不直接使用文件原詞。
- 無答案問題，預期系統明確說「未找到」。
- 過期來源與互相矛盾的問題。

相同問題分別跑：

1. 現行 `query-project-history`／直接 repository search baseline。
2. Knowledge Wiki query。

### PoC 指標

| 指標 | 初始門檻 |
|---|---|
| Material claim citation precision | 100% |
| Verified 頁面的 unsupported material claims | 0 |
| Expected source 出現在 top 5 | 至少 80% 問題 |
| `rejected`／`superseded` 被誤當現行答案 | 0 |
| 無答案問題正確 abstain | 100% |
| Fixture 中的 source drift 偵測 | 100% |
| 使用者評為比 baseline 更有用 | 至少 70% 問題 |
| 每次 ingest 人工 review 中位時間 | PoC 後量測，不先假定 |

若 Wiki 只讓回答變長、引用變多，卻沒有提高 expected-source recall、正確 abstention 或
使用者任務成功率，不算有效。

## 工作流

### Ingest

```text
使用者指定 exact source
→ 驗證 workspace / repository allowlist
→ 固定 commit 或計算 digest
→ 將來源包在不可信資料邊界內
→ 產生 candidate manifest 與 Wiki diff
→ deterministic validation
→ LLM critique（可選）
→ 人工 review
→ promotion PR
→ merge 後更新 index / log
```

限制：

- 不接受無範圍的「掃描所有專案」。
- 原始文件中的 prompt、指令或工具呼叫一律視為資料，不得執行。
- 不移動、改寫或刪除原始來源。
- schema 變更不能夾帶在一般 ingest。
- 失敗 ingest 不留下部分正式頁面。

### Query

```text
問題
→ 選擇 query-project-history 或 Knowledge Wiki
→ 讀 index
→ 讀最相關 verified/reviewed pages
→ 解析 source manifest
→ 重要結論回讀原始來源
→ 回答並顯示狀態與引用
```

- 預設唯讀，不因 query 自動修改 `log.md` 或生成 synthesis。
- 沒有 evidence 時必須 abstain；通用知識回答與 workspace evidence 明確分段。
- `candidate`、`needs-evidence`、`stale` 可作線索，但必須顯示狀態且不能冒充正式事實。

### Lint

第一階段只報告：

- schema 與 frontmatter 問題。
- dead links、orphan pages、duplicate IDs、index drift。
- source 不存在、commit 不可解析、digest drift。
- stale、superseded 與 lifecycle 不一致。
- 缺少引用、引用 candidate、互相矛盾的主張。
- secrets、越界路徑與不受允許的檔案類型。

任何自動修復、頁面合併、刪除或狀態升格都必須是獨立、可預覽且經授權的動作。

## 安全與信任邊界

- 外部來源是不可信輸入；其內文可能包含 prompt injection。
- Query adapter 預設只取得 workspace 讀權限，不取得寫權限。
- Ingest writer 只能寫 `candidates/`；promotion 由 Git PR 完成。
- 原始來源、Wiki、schema 與 validator 分開授權。
- Private workspace 不等於可保存秘密；仍需 secret scan 與資料分類。
- 外部模型只收到完成當次任務的最少資料；敏感來源優先使用本機模型或不攝取。
- Workspace root 必須用 canonical path 驗證，拒絕 traversal 與跳出 allowlist 的 reparse
  point。

## 與現行 projectD 能力的分工

| 能力 | 權威內容 | 用途 |
|---|---|---|
| `vault/memory` | 少量確認摘要 | Session 初始化索引 |
| `query-project-history` | 原專案 HistoryRecord、Git、文件 | 查決策、失敗方案與歷史證據 |
| Knowledge Wiki | 經審核的跨來源 Markdown 綜合 | 查概念、比較、關係與 synthesis |
| 原專案 repo | 原始碼、ADR、測試、正式文件 | 最終 source of truth |

Knowledge Wiki 不得把 `query-project-history` 的 `experimental`、`failed`、`rejected` 或
`superseded` 狀態移除後重新包裝成現行推薦。

## 擴充場景：System Feature Wiki

### 可行性判斷

把系統現有功能整理成 Wiki，供後續功能修改、影響分析與教育訓練查詢，**適合納入本計畫**。
但應整理「系統能力與行為」，而不是讓 LLM 對整個 codebase 逐檔產生摘要。

可行性依自動化程度不同：

| 形式 | 可行性 | 判斷 |
|---|---|---|
| 人工選定重要功能，LLM 產生候選頁面後 review | 高 | 建議 PoC |
| 從 spec、ADR、測試、API 與程式入口增量更新 | 中高 | 完成 PoC 後導入 |
| 自動掃描整個 codebase 並宣稱完整功能文件 | 低 | 容易過期、誤判與產生大量噪音 |
| 直接由 Wiki 驅動正式變更，不回讀程式與測試 | 不接受 | Wiki 不是 source of truth |

它解決兩個不同需求：

1. **功能修改**：快速定位功能行為、使用者流程、相關 repository、程式入口、測試、資料與
   上下游依賴。
2. **教育訓練**：依角色解釋系統能做什麼、如何操作、常見例外、名詞、權限與實際案例。

### Feature Wiki 的資訊層級

```text
System
├─ Capability          # 系統提供的能力
│  ├─ User Flow        # 使用者／操作流程
│  ├─ Business Rule    # 行為與限制
│  ├─ Exception        # 失敗、邊界與替代流程
│  └─ Training View    # 角色導向教材
├─ Integration         # 外部系統與資料交換
└─ Implementation Map  # repo、component、API、test、ADR 的定位索引
```

Wiki 主要回答「系統做什麼、為什麼、會影響哪裡」。具體實作仍由 source pointers 指向
原始碼、測試與正式文件，不把 class、function 或每個檔案內容複製進 Wiki。

### Feature page schema

```yaml
---
schema_version: 1
id: intentype-global-hotkey
type: feature
lifecycle_status: candidate
evidence_status: inferred
system: intentype
audiences:
  - developer
  - support
owners: []
repositories:
  - intentype
source_manifests:
  - intentype-hotkey-spec
  - intentype-hotkey-tests
last_verified: null
---
```

正文至少包含：

```markdown
# 功能名稱

## 使用者價值
## 適用角色與權限
## 前置條件
## 主要流程
## 例外與失敗行為
## 輸入、輸出與資料影響
## 上下游功能與外部整合
## 修改影響地圖
## 驗證入口
## 教育訓練
## 來源
```

`修改影響地圖` 只保存定位資訊：

- repository 與 bounded path。
- API／command／UI entry point。
- 主要 domain module。
- acceptance test、integration test 與人工驗證步驟。
- 相關 spec、ADR、HistoryRecord、Issue 與 release。
- 直接上游、下游與共享資料契約。

不得把未經工具確認的「可能 caller」或「看起來相關」寫成 verified dependency。

### 修改功能時的查詢流程

```text
「我要修改功能 X」
→ Feature Wiki 定位 capability / flow
→ 顯示現行行為、限制與已知例外
→ 顯示 repo、entry point、tests、ADR、上下游
→ Agent 回讀最新 code / test / Git
→ 進行 impact analysis
→ to-spec / to-tickets / implement / code-review
→ 合併後產生 Feature Wiki update candidate
```

Feature Wiki 是 wayfinder，不是 change authority。任何修改建議都必須重新確認目前 branch 的
程式碼與測試，不能只依 Wiki 頁面實作。

### 教育訓練視圖

同一份 verified Feature page 可以衍生不同角色的 training view：

| 角色 | 顯示重點 |
|---|---|
| 新進開發者 | 系統能力、domain terminology、entry point、測試與常見陷阱 |
| 維運／客服 | 操作流程、權限、可觀察症狀、錯誤處理與 escalation |
| PM／SA | 使用者價值、規則、限制、相依功能與決策來源 |
| 使用者 | 操作方式、範例、預期結果與已知限制；排除內部敏感實作 |

教育訓練內容必須由 verified Feature page 衍生，不能建立另一套無來源的平行教材。對外教材
另需檢查秘密、內部路徑、安全設計與未公開能力，不能直接輸出 developer view。

### Feature page 的正確性

功能頁的證據至少包含：

1. **行為證據**：approved spec、acceptance test、可重現操作或正式使用者文件。
2. **實作定位**：目前 commit 上可解析的 bounded code path 或 symbol。
3. **驗證證據**：測試名稱、測試結果來源或可重跑的人工步驟。
4. **決策證據**：ADR、HistoryRecord、Issue 或 user-confirmed rule。
5. **時間證據**：`last_verified` 與來源 commit／digest。

狀態判斷：

- 只有 code shape、命名或 LLM 推論：`candidate / inferred`。
- 行為已由測試支持，但使用者價值或規則未確認：`reviewed` 或 `needs-evidence`。
- 行為、限制、定位與驗證皆可回讀：`verified`。
- 關聯來源變更或測試移除：自動降為 `stale`。

### 更新機制

PoC 不做背景掃描。使用下列明確事件產生 update candidate：

- 功能 PR 合併，且 diff 命中既有 Feature page 的 source manifest。
- Spec、ADR、API contract 或 acceptance test 變更。
- 使用者明確要求新增／更新功能文件。
- Lint 發現 source digest 漂移、失效路徑或矛盾。
- 教育訓練時發現實際系統行為與 Wiki 不一致。

更新仍走：

```text
source change
→ candidate diff
→ deterministic validation
→ feature owner / developer review
→ promotion PR
→ verified
```

不因程式碼 diff 命中頁面就自動重寫正式內容；若無法確認語意影響，只標成 `stale` 並要求
review。

### Feature Wiki lint

除一般 Knowledge Wiki lint 外，增加：

- repository、path、symbol、test 是否仍存在。
- Feature page 是否至少有一項行為證據與驗證入口。
- `as-is` 現行行為與 `to-be` 規劃是否混在同一段落。
- 同一 capability 是否建立重複頁面。
- 上下游連結是否互相一致。
- 已下線功能是否仍標成 active。
- Training view 是否引用 stale／candidate 內容。
- 對外教材是否洩漏內部路徑、敏感權限或安全實作。

### System Feature Wiki PoC

先選 5–10 個高價值功能，而非整個系統：

- 經常修改或跨多模組的功能。
- 新進人員最常詢問的流程。
- 曾因理解錯誤造成 bug 或重工的功能。
- 有明確 spec、測試與程式入口可驗證的功能。

PoC 驗收：

- 開發者能在頁面中找到正確 repository、entry point、tests 與 ADR。
- 用 Feature Wiki 做 impact analysis 時，沒有漏掉 benchmark 預先標記的主要上下游。
- 新進人員能依 training view 完成指定操作或回答固定問題。
- 功能來源變更後，lint 能把相關頁面標為 `stale`。
- Feature Wiki 相較直接搜尋文件，降低重複探索但不增加錯誤信心。
- 建立與維護頁面的 review 成本可接受；若成本高於直接維護正式文件，停止擴張。

## 對 `jason-effi-lab/karpathy-llm-wiki-vault` 的採用判斷

可借鑑：

- `raw`／`wiki`／schema 分層。
- `index.md`、append-only operation log。
- `ingest`、`query`、`lint` 的小型工作流。
- 衝突不靜默覆蓋。
- Lint 先報告、修復再確認。

必須重寫：

- `raw` 宣稱 immutable，卻在 ingest 後搬至 archive 的矛盾。
- Query 每次強制寫 log，不符合核心唯讀 adapter。
- Ingest 可隱式觸發並廣掃 inbox。
- 只有 raw path，缺少 repository、commit、digest 與 evidence lifecycle。
- Claude 專用 `.claude/skills`、`CLAUDE.md`、`user-invocable` metadata。
- 強制簡體中文，不符合 projectD 跨 Agent 與使用者語言需求。
- Lint 缺少 source drift、schema、provenance、secret 與 lifecycle checks。
- README 宣稱的 `obsidian-cli`／`defuddle` 與實際 Skill 目錄不一致。

授權閘門：

- 研究時 repository root 未見 `LICENSE`，GitHub Contents API 查詢 `LICENSE` 為 404。
- 未取得明確授權前，只把它當設計證據；不得複製或改寫其 Skill 文字進 projectD。
- projectD 實作必須從需求與 Karpathy 抽象模式獨立撰寫，並保留來源說明。

## 分階段計畫

### Phase 0：決策與邊界

- [ ] 決定是否建立獨立 private repository。
- [ ] 確認 workspace path、允許來源、資料分類與 reviewer。
- [ ] 將已接受架構寫成 ADR；本計畫本身不視為 ADR。
- [ ] 決定 PoC benchmark 與 baseline。

### Phase 1：手動 Wiki PoC

- [ ] 建立空 workspace，不複製外部範例知識。
- [ ] 定義 source manifest 與 Wiki page schema。
- [ ] 手動建立 10–20 個 verified 頁面。
- [ ] 建立 deterministic validator 與 fixture。
- [ ] 建立只讀 `knowledge-query` tracer bullet。

### Phase 2：Candidate ingest

- [ ] 只支援 exact file／commit。
- [ ] 產生 candidate diff，不直接寫正式 Wiki。
- [ ] 加入 prompt-injection boundary、secret scan 與 source digest。
- [ ] 建立 promotion review 與 PR 流程。

### Phase 3：Lint 與生命周期

- [ ] 檢查 links、index、schema、digest、drift、duplicate 與 lifecycle。
- [ ] 驗證 stale／superseded／rejected 不會被誤用。
- [ ] 修復動作與唯讀 lint 分離。

### Phase 4：有效性評估

- [ ] 對相同 benchmark 跑 baseline 與 Wiki query。
- [ ] 人工審核來源命中、引用精度、abstention 與答案實用性。
- [ ] 記錄 ingest review 成本與 Wiki 維護成本。
- [ ] 只有達到門檻才考慮 Git 同步、全文搜尋、MCP 或更大規模。

## PoC 驗收條件

- 核心 session init 不載入外部 Wiki。
- `knowledge-query` 在 OS 與 Git 層面皆為唯讀。
- 每個正式頁面的 material claims 都能追到固定來源。
- Candidate 不會進入正式答案，除非明確顯示其非正式狀態。
- Source drift 能被 fixture 與實際變更重現。
- 無答案問題不會被模型補寫成看似有來源的答案。
- 所有寫入都限定外部 workspace，且 promotion 經 PR。
- 相較 baseline 達到本計畫的正確性與有效性門檻。

## 停止或縮減條件

符合任一條件即停止擴張，回到唯讀 prototype 或取消導入：

- Wiki 未顯著改善 benchmark，只有額外摘要與維護成本。
- Verified 頁面仍反覆出現 unsupported material claims。
- 人工 review 成本高於直接查原始專案。
- Source drift、重複頁面或 schema migration 無法可靠治理。
- 敏感資料無法在現有 provider 與儲存方式下隔離。
- Agent 必須取得過廣的檔案或網路權限才能運作。

## 待確認決策

- 外部 repo 名稱、位置及是否使用 Obsidian。
- 初始允許攝取的專案與文件類型。
- `verified` 的 reviewer 與高風險內容核准者。
- Candidate、log 與 rejected 頁面的保留期限。
- 是否需要繁體中文為預設，或依來源／使用者語言生成。
- 達到什麼規模才導入全文／hybrid search。

## 來源

- Andrej Karpathy, LLM Wiki：
  <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>
- `jason-effi-lab/karpathy-llm-wiki-vault`：
  <https://github.com/jason-effi-lab/karpathy-llm-wiki-vault>
- 目標 repository 的治理與 Skills：
  - <https://github.com/jason-effi-lab/karpathy-llm-wiki-vault/blob/main/CLAUDE.md>
  - <https://github.com/jason-effi-lab/karpathy-llm-wiki-vault/blob/main/.claude/skills/ingest/SKILL.md>
  - <https://github.com/jason-effi-lab/karpathy-llm-wiki-vault/blob/main/.claude/skills/query/SKILL.md>
  - <https://github.com/jason-effi-lab/karpathy-llm-wiki-vault/blob/main/.claude/skills/lint/SKILL.md>
- projectD 現行治理與歷程查詢：
  - [`operating-model.md`](operating-model.md)
  - [`query-project-history`](../../core/skills/query-project-history/SKILL.md)
