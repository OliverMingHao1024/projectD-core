# System Feature Wiki PoC

> **狀態：approved / Phase 0 in progress（intentype 與 lbib 兩個 source system）**
>
> 本規格是第一階段實作與驗收的權威。既有
> [`plan-external-llm-wiki.md`](../../vault/governance/plan-external-llm-wiki.md)
> 只保留為研究背景；內容若與本規格或 ADR 0004–0009 衝突，以本規格與 ADR 為準。
> ADR 0013 將 Phase 0 基礎設施（schema／validator／registry）擴大為系統無關建置，
> `lbib` 與 `intentype` 並列為受管來源系統；衝突時以 ADR 0013 為準。

## Problem

projectD-core 已能管理治理、Skill 與已驗證的專案歷程，但在修改既有系統功能前，Agent
仍需反覆探索使用者行為、程式入口、測試、ADR 及上下游影響。逐檔摘要容易過期，也無法
穩定回答「這項功能做什麼」與「修改它會影響哪裡」。

第一階段不處理廣泛外部技術知識。PoC 只驗證：受治理的 SystemFeatureWiki 是否能改善
`intentype` 功能修改前的定位與影響分析，同時維持來源可追溯、過期可見及 fail-closed。

## Outcome

建立獨立 private KnowledgeWorkspace：

```text
D:\workspaces\projectD-knowledge
```

- 以使用者可觀察能力建立 FeaturePage，不建立 module、class 或逐檔摘要頁。
- 每個正式 FeaturePage 都固定來源 commit、bounded paths 與 content digest。
- Query 先做 deterministic lexical retrieval，再回讀 manifest 與最新 code/test。
- LLM 只能產生 candidate diff；只有通過 validator 且經 repository owner 核准的 PR
  能執行 KnowledgePromotion。
- projectD-core 保持精簡，不在 session 初始化載入 Wiki，也不保存 Wiki 內容或具體 schema。

## Authority and repository boundaries

| 邊界 | 擁有內容 | 不擁有 |
|---|---|---|
| `intentype`（source system） | 程式碼、測試、spec、manual、ADR、HistoryRecord | Wiki synthesis |
| `lbib`（source system；對應 `lbib_Web`、`lbib_Trade_New`、`lbib_PlatformDll_New` 三個 git repository） | 程式碼、測試、spec、ADR、Vault 文件 | Wiki synthesis |
| `projectD-knowledge` | manifest/page schema、validator、fixtures、CI、正式 FeaturePage、index | 原始碼與正式產品決策 |
| `projectD-core` | workspace registry 規則、支援的 schema version、生命周期與安全底線、query/lint adapter | 具體 schema、validator 或 Wiki 內容 |

一個 source system 可對應多個 git repository：`repository_id` 是單一 repository 的
resolvable key，`system` 是頁面切分與 query 範圍所用的較上層分組。`lbib` 的三個
repository 各自有獨立 commit history；跨 repository 的單一能力頁需在
`source_manifests` 陣列中同時引用對應 repository 的 manifest。

來源 repository 永遠是最終 source of truth。SystemFeatureWiki 是 wayfinder，不是 change
authority；Agent 不得只依 Wiki 實作功能變更。

## PoC scope

### Source system

第一階段納入兩個 source system：

- `intentype`：單一 git repository。
- `lbib`：跨 `lbib_Web`、`lbib_Trade_New`、`lbib_PlatformDll_New` 三個 git
  repository（LBIB 容器目錄本身不設 git repo，不是 source）。

ADR 0013 記錄此擴大範圍的決策；Phase 0 基礎設施（schema／validator／registry）
系統無關，兩個 source system 共用同一套工具與生命週期規則。

### Primary use case

開發者或 Agent 在修改功能前：

1. 找到現行使用者行為、限制與已知例外。
2. 找到 repository、entry point、主要 domain module、tests、ADR 與 HistoryRecord。
3. 找到直接上下游與共享資料契約。
4. 回讀目前 branch 的 code/test，再進行 impact analysis。
5. 銜接 `to-spec` → `to-tickets` → `implement` → `code-review`。

Training view 只可作最小衍生展示，不是第一階段硬性驗收。

### Initial FeaturePages

PoC 固定建立以下八頁：

1. 推按快捷鍵與麥克風錄音。
2. 語音轉錄、潤飾與工作流狀態。
3. 原始目標保存與安全文字插入。
4. Provider 偵測、選擇、隱私確認與程序隔離。
5. Local Only deterministic cleanup。
6. 模型下載、驗證、載入與 idle unload。
7. 個人詞彙、低信心提示與修正學習。
8. 診斷資料保存、預覽與匯出。

UI 外觀、聲音提示、打包／發布與廣泛外部技術知識不在本 PoC。

`lbib` 的 Initial FeaturePages 尚未選定，是獨立於 Phase 0 基礎設施建置的後續決策；
選定前 `wiki/systems/lbib/` 不建立任何 candidate 或 verified 內容。

## Domain rules

### FeaturePage boundary

FeaturePage 必須以單一使用者可觀察能力為邊界。程式模組、class、symbol 與檔案只能出現
在 Implementation Map，不能成為切頁依據。

### Language

- 正文預設繁體中文。
- 程式 identifier、API、錯誤文字、路徑與正式產品名稱保留來源語言。
- `id`、schema key 與 enum 固定英文。
- `aliases` 可包含中英文查詢詞。
- 不為同一能力維護中英文兩份頁面。

### Lifecycle

```text
candidate
  ├─ verified
  ├─ needs-evidence
  └─ rejected

verified → stale
verified → superseded
```

`reviewed` 不是頁面狀態。Review 是 promotion PR 上的事件；「有人讀過」不能代表主張已
由來源證實。

- 正式 query 預設只使用 `verified`。
- `candidate`、`needs-evidence` 與 `rejected` 只存在於未合併或已關閉的 PR。
- `stale` 與 `superseded` 保留於 Git 歷史或明確 audit 入口，不進正式 query index。
- 沒有 `verified` 答案時必須 abstain，不得用其他狀態補寫答案。

`evidence_status` 使用 projectD 既有證據語言：

- `verified`：可由 pinned source、測試或正式文件直接支持。
- `user-confirmed`：由 reviewer 明確確認，但缺少完整可回讀證據。
- `inferred`：由來源推論，只能留在 candidate／needs-evidence。
- `unknown`：沒有足夠證據，只能留在 candidate／needs-evidence。

頁面要升為 `lifecycle_status: verified`，中央主張的 `evidence_status` 也必須是 `verified`。
若個別主張等級不同，須在正文附近標示；`user-confirmed`、`inferred` 或 `unknown` material
claim 不能隨頁面升格。

## KnowledgeWorkspace shape

`main` 預期只保存正式內容與驗證工具：

```text
projectD-knowledge/
├─ README.md
├─ schema/
│  ├─ source-manifest.schema.json
│  └─ feature-page.schema.json
├─ sources/
│  └─ manifests/
├─ wiki/
│  └─ systems/
│     ├─ intentype/
│     └─ lbib/
├─ fixtures/
├─ scripts/
│  └─ validate.*
└─ index.json
```

不在 `main` 建立 `candidates/`、`reviews/` 或 append-only `log.md`。Candidate 只存在於
feature branch／pull-request diff；validator 與 CI 結果留在 PR checks。拒絕或證據不足
時關閉 PR 並保留理由；核准後才合併正式頁面。

`index.json` 必須只由 `verified` 頁面 deterministic 產生或驗證，不接受手動維護的
第二份狀態。其他 lifecycle 只能經明確 audit/history 入口讀取。

## Data contracts

以下欄位是 PoC 必須表達的語意；具體 JSON Schema 由 `projectD-knowledge` 擁有。

### Source manifest

```yaml
---
schema_version: 1
id: intentype-safe-text-insertion
source_type: git-path-set
repository_id: intentype
remote_url: https://github.com/<owner>/<repo>
commit: <full-commit-sha>
paths:
  - docs/specs/mvp.md
  - src/intentype/target.py
  - src/intentype/windows_target.py
  - tests/test_target.py
  - tests/test_windows_target.py
content_digest: sha256:...
captured_at: 2026-07-28
sensitivity: internal
---
```

要求：

- committed manifest 不得保存絕對本機路徑。
- Git 來源固定 full commit；manifest 內容與 bounded path set 共同計算 digest。
- `repository_id` 必須能由本機 KnowledgeWorkspaceRegistry 解析。
- 來源不存在、digest 不符或路徑越界時 fail closed。

### FeaturePage

```yaml
---
schema_version: 1
id: intentype-safe-text-insertion
type: feature
lifecycle_status: candidate
evidence_status: inferred
system: intentype
title: 安全文字插入
summary: 保存原始輸入目標並在插入前重新驗證安全條件。
aliases:
  - text insertion
  - password field blocking
source_manifests:
  - intentype-safe-text-insertion
last_verified: null
superseded_by: null
---
```

正文至少包含：

```markdown
# 功能名稱

## 使用者價值
## 前置條件
## 現行主要流程
## 例外與失敗行為
## 輸入、輸出與資料影響
## 上下游與共享契約
## Implementation Map
## 驗證入口
## 來源
```

Implementation Map 只保存可回讀定位：

- repository ID、bounded path 與 source commit。
- UI／API／command entry point。
- 主要 domain module 或 symbol。
- acceptance／integration／unit test。
- spec、ADR、HistoryRecord、Issue／PR。
- 已由工具或正式文件確認的直接上下游。

未經工具確認的「可能 caller」或「看起來相關」不得寫成 verified dependency。

## Evidence allowlist

第一階段只允許已登錄 source system 的 Git repository 內的精確來源：

- `intentype`：approved spec、README、manual、bounded `src/intentype/**`、對應
  `tests/test_*.py`、ADR、HistoryRecord、Issue／PR URL、必要的正式設定或 API
  contract。
- `lbib`（`lbib_Web`、`lbib_Trade_New`、`lbib_PlatformDll_New`）：各 repo 的
  approved spec／`docs/specs/**`、README、對應 bounded 程式路徑、ADR、
  HistoryRecord、Issue／PR URL、必要的正式設定或 API contract。

排除：

- 對話、clipboard、runtime log、診斷匯出。
- `.local`、環境變數、憑證與使用者資料。
- binaries、build／release artifacts、dependency contents。
- 無 commit／digest 的臨時文件。
- 未限定範圍的整個 repository ingest。

每個 `verified` FeaturePage 至少需要：

1. 一項行為證據。
2. 一項可解析的實作定位。
3. 一個可重跑驗證入口。
4. 完整 source manifest 與驗證日期。

Material claim 必須在主張附近引用 source ID 與 path／commit，不能只在 frontmatter
列出來源。

## Local portability and allowlist

每台裝置在 Git ignored 的 `.local/knowledge-workspaces.json` 保存
KnowledgeWorkspaceRegistry：

```json
{
  "schema_version": 1,
  "workspaces": {
    "projectd-knowledge": "D:\\workspaces\\projectD-knowledge"
  },
  "repositories": {
    "intentype": "D:\\workspaces\\intentype",
    "lbib-web": "D:\\workspaces\\LBIB\\lbib_Web",
    "lbib-trade": "D:\\workspaces\\LBIB\\lbib_Trade_New",
    "lbib-platformdll": "D:\\workspaces\\LBIB\\lbib_PlatformDll_New"
  }
}
```

實際路徑可因裝置不同而改變。Adapter 必須：

- canonicalize workspace 與 repository root。
- 只解析明確 allowlist ID。
- 拒絕 `..` traversal。
- 拒絕 symlink／junction／reparse point 跳出 allowlist root。
- 不把本機 path、憑證或敏感環境寫回 committed manifest。

## Workflows

### Candidate authoring and KnowledgePromotion

第一階段不建立自動 `knowledge-ingest`。

```text
使用者選定 FeaturePage 與 exact sources
→ 固定 commit、paths 與 digest
→ AI 在 feature branch 產生 candidate manifest/page diff
→ deterministic validator
→ optional LLM critique
→ repository owner 檢查來源與 diff
→ promotion PR
→ merge 為 verified
```

- AI、validator、CI 或 LLM critique 均不能自行 promotion。
- PoC 唯一 promotion reviewer 是 KnowledgeWorkspace repository owner。
- 安全、隱私、權限與架構主張必須由 reviewer 逐項確認。
- 第一階段所有寫入只發生在 `projectD-knowledge` 的 candidate branch。

### Query

```text
問題
→ 讀取 deterministic index.json
→ lexical ranking
→ 最多讀取前三個 verified FeaturePages
→ 解析 source manifests
→ 檢查 RuntimeStale
→ 回讀最新 code/test
→ 回答並附狀態與來源
```

Lexical ranking 只使用 `system`、`id`、title、aliases 與 summary。第一階段不使用
SQLite、embedding、向量資料庫或 MCP。

Query 預設唯讀，不寫 log、不產生 synthesis、不修改 lifecycle。

### Drift and RuntimeStale

- `knowledge-lint` 手動或 CI 比較 manifest 與來源 default branch，報告持久 drift。
- `knowledge-query` 回答前比較目前來源 workspace 的 HEAD 與 working tree。
- 若 bounded source 已變，query 標示 `runtime-stale`，不得把頁面當成現行事實。
- RuntimeStale 不自動寫回 Wiki；Agent 必須回讀最新 code/test。
- 只有後續 KnowledgePromotion PR 能更新 FeaturePage 與 `last_verified`。

### Lint

第一階段 `knowledge-lint` 只讀報告：

- schema、必要欄位、enum 與 schema version。
- duplicate ID、dead link、orphan page 與 index drift。
- repository ID、commit、path 與 digest 可解析性。
- lifecycle／evidence 不一致。
- material claim 缺少引用。
- 任何非 `verified` lifecycle 進入正式 index。
- secret、絕對本機路徑、越界 path 與 reparse point。
- source drift 與 RuntimeStale fixtures。

任何修復、合併、刪除或狀態升格都必須是獨立 PR。

## Verification strategy

最高穩定介面：

```text
問題
→ knowledge-query
→ verified FeaturePage
→ source manifest
→ pinned source
→ current code/test read-back
```

固定建立 16 題人工審核 benchmark：

- 8 題單一功能定位。
- 4 題跨功能修改影響。
- 2 題 source drift／working-tree 變更。
- 2 題無答案，必須 abstain。

相同問題比較：

1. 直接 `rg`／repository search baseline。
2. deterministic lexical Knowledge Wiki query。

驗收門檻：

| 指標 | 門檻 |
|---|---|
| Expected FeaturePage 出現在 top 3 | 至少 90% |
| Material claim citation precision | 100% |
| Unsupported material claims | 0 |
| Benchmark 標記的主要上下游遺漏 | 0 |
| RuntimeStale／source drift fixture 偵測 | 100% |
| 無答案正確 abstain | 100% |
| 使用者評為比 baseline 更有用 | 至少 70% |
| 每頁建立與 review 時間 | 量測，不預設門檻 |

若 Wiki 只增加摘要與引用，卻沒有改善定位、影響完整性、正確 abstention 或任務成果，
PoC 視為失敗。

## Acceptance criteria

- [ ] `projectD-knowledge` 是獨立 private Git repository。
- [ ] `projectD-core` session 初始化不載入 Wiki。
- [ ] `main` 只含正式內容；candidate/review 只存在於 PR。
- [ ] 具體 schema、validator、fixtures 與 CI 只由 KnowledgeWorkspace 擁有。
- [ ] 八個 FeaturePages 全部以能力切頁。
- [ ] 每頁具備行為證據、實作定位、驗證入口與 pinned manifest。
- [ ] 正式 index 只包含 `verified`。
- [ ] Query 每次最多讀取前三個 verified pages。
- [ ] Query 與 lint 均預設唯讀。
- [ ] Unknown schema、未知 repository ID、digest drift 或路徑越界均 fail closed。
- [ ] RuntimeStale 時不依 Wiki 宣稱現行行為。
- [ ] AI 無法自行執行 KnowledgePromotion。
- [ ] 不保存絕對本機路徑、秘密、runtime log 或使用者內容。
- [ ] 通過 16 題 benchmark 的全部硬門檻。

## Delivery phases

### Phase 0 — Workspace and contracts

- 建立 private `projectD-knowledge`。
- 定義兩份 schema、fixture、validator 與 branch protection／CI。
- 建立本機 KnowledgeWorkspaceRegistry。
- 建立八頁空白 candidate skeleton。

### Phase 1 — Manual verified pages and query tracer bullet

- 逐頁選定 exact sources 並產生 candidate PR。
- 完成八頁 promotion review。
- 產生／驗證 deterministic `index.json`。
- 建立最小 `knowledge-query` 與唯讀 `knowledge-lint` adapter。

### Phase 2 — Effectiveness evaluation

- 建立並審核 16 題 benchmark。
- 比較 direct search 與 Wiki query。
- 記錄 review 成本與錯誤類型。
- 依停止條件決定繼續、縮減或取消。

### Deferred

只有 PoC 達標後才另案評估：

- exact-source `knowledge-ingest`。
- 外部技術知識與跨來源 synthesis。
- Training view 正式驗收。
- 全文／hybrid search、embedding、向量資料庫或 MCP。
- 背景掃描、Git hook、自動排程或自動更新。
- Obsidian 或其他特定知識工具。

## Stop conditions

符合任一條件即停止擴張：

- Wiki 未達 benchmark，或只讓回答更長。
- Verified 頁面出現 unsupported material claims。
- 主要上下游仍反覆遺漏。
- Drift、schema 或路徑邊界無法可靠 fail closed。
- 人工 review 成本高於直接維護／搜尋正式文件。
- Agent 需要過廣的檔案或網路權限。
- 敏感資料無法在現有儲存與 provider 邊界內隔離。

## References

- [projectD domain language](../../CONTEXT.md)
- [ADR 0004：能力切頁](../adr/0004-organize-feature-wiki-by-capability.md)
- [ADR 0005：獨立 KnowledgeWorkspace](../adr/0005-separate-knowledge-workspace.md)
- [ADR 0006：Review 是事件](../adr/0006-treat-review-as-event.md)
- [ADR 0007：PR promotion audit](../adr/0007-use-pull-requests-for-knowledge-promotion.md)
- [ADR 0008：Drift 不自動修改](../adr/0008-detect-feature-page-drift-without-mutation.md)
- [ADR 0009：Portable manifests](../adr/0009-keep-knowledge-manifests-portable.md)
- [ADR 0013：擴大範圍至 lbib](../adr/0013-expand-knowledge-workspace-to-lbib.md)
- [歷史研究計畫](../../vault/governance/plan-external-llm-wiki.md)
- [projectD 運作模型](../../vault/governance/operating-model.md)
- [query-project-history](../../core/skills/query-project-history/SKILL.md)
- [`intentype` MVP spec](../../../intentype/docs/specs/mvp.md)
- [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
