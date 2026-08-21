---
lastUpdated: 2026-08-22
---

# 記憶快照

<!-- 每次重要決策後更新。格式：日期 + 決策 + 為什麼。 -->

## 2026-07-24

- 從零建立 projectD-core，作為個人獨立擁有、精簡且可按需演進的 AI 治理核心。
- 採用自主設計的 core + packs 架構。
- 所有自建 Skill 採開放的 `<name>/SKILL.md` 格式，canonical 內容只在 projectD-core 維護：
  `core/skills/` 放跨技術棧能力、`packs/` 放技術棧規範；`setup.ps1` 只以 junction 接到
  `~/.claude/skills/` 與 Codex/Copilot 共用的 `~/.agents/skills/`，不為不同 AI 維護副本。
- 角色 agent：PM/SA/SD/PG 四個獨立具名 agent。
- 初始 pack：csharp、frontend-core、frontend-react、frontend-angular、typescript / node-runtime、python（骨架，內容待實際使用累積）。
- 建立輕量 L1–L6 運作模型：L0 常駐、其他層按語意載入；四角色依任務規模選用，
  不強制完整流水線，也不引入固定思維框架、自動 recap 或跨專案固定覆蓋率。
- Fleet 專案以 `AGENTS.md`／`CLAUDE.md`／`GEMINI.md` 受管區塊連回單一 core，
  並用 `scripts/fleet-governance.ps1` 的 Apply／Check 模式防止入口漂移或靜默失聯。

## 2026-07-26

- 為避免外部 Skill 或單一套件清單造成跨專案生態綁定，採用「共用決策原則 → 能力需求 →
  技術棧 adapter → 專案決策」四層模型。L0 只保留技術生態中立底線；具體路由放在 L4。
  新增 `select-frontend-capability`，React／Angular 候選留在各自 adapter，且只能作為附帶
  適用條件的候選。專案既有決策與可維護依賴優先，只有需求、維護、安全、授權、相容性、
  成本或使用者要求發生變化時才重新選型。
- 從 `emilkowalski/skills` 部分收錄並改寫 `apple-design`、`animation-vocabulary`、
  `design-engineering`、`find-animation-opportunities`、`improve-animations` 與
  `review-animations`。修正來源中的絕對動效規則、spring／效能保證、跨框架與寫入授權問題；
  原版 `pick-ui-library` 不建立 active Skill，只把附帶條件的候選整合至 React adapter。

## 2026-07-27

- 為避免 Git 只留下「改了什麼」而遺失「為什麼」，建立重要決策／可重複教訓的最小留痕
  閉環：L0 要求重要理由可追溯且禁止事後捏造；L5 定義觸發條件與
  `verified`／`user-confirmed`／`inferred`／`unknown` 證據分級；L6 在任務結束時由 AI
  提出候選，使用者只需選擇保留、暫留或排除。一般修改不產生流水帳，完整對話不保存。

## 2026-07-28

- 外部 Skill 引入改為定向、受治理流程：`skill-scout` 只接受功能需求或明確 GitHub
  Skill 來源，最多三組查詢與三個合格候選，不自動擴大範圍、執行外部程式、寫 staging
  或收錄。Claude `/skill-scout` 只作薄入口；Claude、Codex、Copilot 共用 canonical Skill。
- Skill 管理採 `SkillSource`（repository）與 `SkillCandidate`（單一路徑）兩層模型；
  `skill-registry.json` 保存機器狀態，`skill-candidates.md` 保存人工理由。候選 ID 包含
  repository 與完整 Skill 路徑，staging 分離 immutable `upstream/` 與 `adapted/`。
- CanonicalSkill 的正式落點依適用範圍決定：跨技術棧放 `core/skills/`，特定技術棧放
  `packs/`；來源是否外部不再決定落點。upstream 更新由獨立 `skill-update-check` 唯讀
  比對路徑 digest，任何採用或升級仍需使用者確認。
- System Feature Wiki 第一階段收斂為 `intentype` 開發影響分析 PoC：八個 FeaturePages
  以使用者可觀察能力切頁，內容放在獨立 private `projectD-knowledge`；來源 repo 仍是
  最終權威。KnowledgeWorkspace 擁有具體 schema、validator、fixtures 與 CI，
  projectD-core 只保留 portable allowlist、生命周期／安全底線與 fail-closed adapter。
- KnowledgePromotion 只透過 GitHub PR；`reviewed` 是事件而非頁面狀態。PoC 使用
  deterministic lexical index、lint drift 與 query RuntimeStale 防呆，延後自動 ingest、
  外部技術知識、hybrid search 與正式 training view。

## 2026-08-19

- 比對 BMAD-METHOD（GitHub 52k+ stars，五角色：Analyst/Architect/Dev/PM/UX Designer）後，
  新增 `ux`（UX designer）角色 agent，補上原本 PM/SA/SD/PG 四角色缺少的獨立使用者互動／
  易用性設計階段。角色順序調整為 PM → SA → UX → SD → PG：SA 判斷是否需要 UX 與／或 SD，
  UX 產出互動流程／狀態契約並決定適用的 design 類 Skill，SD 據此設計架構／資料模型，
  PG 依契約實作並驗證。
- 同步更新 `core/constitution/rules.md`（角色邊界）、`vault/governance/operating-model.md`
  （L3 路由表）、`README.md`、`CLAUDE.md`、`fleet/README.md` 與
  `scripts/ProjectD.GovernanceWiring.psm1` 的受管區塊文字，維持角色清單單一事實來源；
  `core/agents/` 由既有 junction-free 複製機制自動接到 `~/.claude/agents/ux.md`，
  不需改動 GovernanceWiring 邏輯本身。
- 未採用 BMAD 的其他部分：`bmad-loop`（無人值守自動 epic 建置）與 TaskScopedProposalLoop
  明確排除的 ProactiveMonitoring／AutonomousWorkflow／ContinuousAgentLoop 直接衝突，
  故不引入；PRD/PRFAQ 等更細顆粒度規劃文件目前無實際踩坑，依 L0 第 8 條暫不新增，
  待實際需求出現再評估。
- 使用者確認後新增 `qa`（獨立於實作者的測試涵蓋率／驗收驗證）角色 agent，對應 BMAD 的
  `tea`（Test Architect）／`bmad-qa-generate-e2e-tests`。角色鏈延伸為
  PM → SA → UX → SD → PG → QA：PG 完成實作與自身 TDD 循環後，視複雜度／風險/使用者可見
  程度決定是否交 QA 做獨立驗證；QA 只讀＋執行測試／建置工具，不寫入 test 或 production
  檔案，發現落回 PG 修正，藉此與既有 `code-review` skill（diff 對 Standards／Spec 兩軸）
  區隔：code-review 是任何角色都能用的靜態 diff 審查 skill，QA 是動態執行測試、獨立於
  實作者驗收涵蓋率的角色。
- 評估 `bmad-forge-idea`／`bmad-brainstorming`／`bmad-advanced-elicitation` 後，判定既有
  `grilling`／`grill-with-docs` 只涵蓋「收斂式、單一視角釐清」，未涵蓋對抗式多角色質詢
  （attack/defend）、正式 Kill 結局、結構化批判方法選單、真正發散式腦力激盪。三者皆綁定
  `_bmad/` runtime（`uv`、Python script、memlog、HTML 頁面），不符合本 repo 自包含
  `SKILL.md` 的 Skill 格式，需改寫而非照搬。使用者選擇先備用，待實際遇到 grilling 問不出
  結果或需要先發散選項的情境再動手，暫不建立新 skill。
- 評估 `bmad-deep-recon` 後，只採用「候選方案比較」這個子能力，寫成 `research` skill 的
  新增段落「Comparing candidates」：先定客觀比較欄位、逐一向權威來源查證、確認事實與
  搜尋摘要印象分開、按驗證結果而非搜尋排序推薦。採用理由是本 session 比較 GitHub 上
  類似專案時已實際用到且發現落差（先泛列連結，查證後才發現兩個候選已停滯）；`selection.md`
  的完整方法論、Draft／Process／Run 三種服務模式，以及市場/競品等六種類型包，皆無實際
  踩坑證據，依 L0 第 8 條不採用。

## 2026-08-21

- 使用者確認保留 Governance Evals v2 Phase 1：既有 structural eval 之外，新增 12 個
  behavior cases 與 deterministic offline grader，以及 11 項 repository-verifiable
  governance asset inventory；三者均接入 `projectd-check` 與 CI。
- Phase 1 刻意維持 provider-neutral、local-first：不呼叫付費模型 API、不把秘密放入測試，
  以 redacted trace／final state 與 SHA-256 integrity 作為可重播證據；host runtime 的實際
  model、credential、MCP process、sandbox 與 egress 明列為 coverage exclusions。
- 完整決策、替代方案、驗證與限制保存在
  `docs/history/2026-08-21-governance-evals-v2-phase-1.md`；目前已通過六個 PowerShell
  contracts、`projectd-check` 11/11、3 個 Python unittest 及修正後的 security／code review。
- 使用者接續核准 Governance Evals v2 Phase 2：新增 8 個 metadata-only synthetic traces，
  覆蓋 prompt injection、memory poisoning、tool misuse、exfiltration，以及 credential revoke、
  tool disable、egress deny、rollback；append-only chain、action budget、秘密 marker、未授權成功
  action 與 observable final state 均由 deterministic validator 驗證。
- Phase 2 保持 fail closed：`host-captured` 必須等授權 adapter、provenance 與 integrity contract；
  尚無 accepted／verified 真實 incident，因此只保留明示的 `no-verified-incidents` exclusion，
  不以 synthetic drill 冒充事故證據。
- Phase 2 決策與限制保存在
  `docs/history/2026-08-21-governance-evals-v2-phase-2.md`；文件對齊時重新執行
  `projectd-check -SkipGlobal -GovernanceEvals` 為 12/12。當時 Phase 3／4 尚未開始，下一缺口是
  真實 host trial、跨模型／跨 host 相容性、checkpoint recovery 與效果量測。

## 2026-08-22

- 使用者核准 Governance Evals v2 Phase 3 採 Codex-first：完成 host trial envelope 與 task
  checkpoint schemas、Codex metadata-only 手動匯入 adapter、deterministic validator、contract
  tests、asset inventory、`projectd-check` 與 CI wiring；adapter 不啟動模型，輸出只進 Git ignored
  的 `.local/governance/`。
- 安全與 code review 共修正三項 material：未做 current workspace check 時不得回報可續跑；
  失敗 trial 必須保留且 high／critical regression 不得被平均；只有 canonical recovery case
  實際通過才可能 `safe_to_resume`。修正後 focused security／code re-review 均通過。
- Codex-first 已追加 baseline／candidate paired upgrade gate：兩側 manifest 先通過同一 validator，
  並固定 evidence kind、host／harness／adapter、catalog digest、case set 與逐 case trial count；
  候選版 high／critical 失敗、passed count 下降或 behavior input contract 無效即阻擋，缺少的
  token／cost delta 維持 `unavailable`。目前仍未執行真實
  Codex pilot／paired evidence，當時也未完成 Claude／Copilot adapters 與三 host compatibility matrix；
  手動提供的 model version 明示為 `user-supplied`，不可冒充 host 自動證明。
- Phase 3 再加入 Claude adapter contract：host envelope 已 provider-neutral 化為 Codex／Claude，
  shared grader 會綁定 host 與 adapter identity；本機 Claude Code CLI `2.1.229` 已確認可用，
  adapter 仍只做 metadata-only 手動匯入，不自行啟動模型。後續已加入 paired-pilot run-plan
  contract，固定完整 model ID、instruction／fixture digest、observer coverage、plan-only
  permission、session 不持久化與 subscription-only 零額外支出；訂閱額度耗盡即停止等待，
  不得切換 API 或 usage credits。Validator 只做投影且不啟動模型。實際
  tool-event／filesystem／smoke-test observers 與 live runner 仍待實作，不能把模型自述當作完成證據。

## 2026-07-30

- TBB／LBIB「新增交易代碼」Skill 依實際程式碼的 parameterized SQL 慣例撰寫；舊資料庫標準文件與程式碼不符，不作為權威來源。
- `rdl-report` 已成為 projectD-core 的 canonical pack，並吸收 LBIB 參數、資料集與版面線索；重疊的 `ssrs-rdl` 副本與失效 junction 已移除。
- oai-core 的重疊 `bug-fix` 與 `code-review` 已移除，避免功能重疊與 junction 覆寫風險；其餘無對應且尚無淘汰證據的 Skills 繼續保留。

## 2026-08-18

- 採用 TaskScopedProposalLoop 作為實際執行與產物任務的外層治理流程：
  `Understand → Propose → Authorize → Execute → Verify → Report → Learn`。
  此流程只處理使用者提出或既有授權範圍內發現的工作，不包含背景監控、未授權跨工具觀察或自行擴張範圍。
- 只有具實質影響的發現形成 MaterialProposal；既有範圍內必要、低風險且可回復的操作沿用原授權。未接受提案只回報、不自動持久化；軟體工程的 Spec、Tracer-bullet TDD 與雙軸 Review 分別組合於 Execute／Verify。
