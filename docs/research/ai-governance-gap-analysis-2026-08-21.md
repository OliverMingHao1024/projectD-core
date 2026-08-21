# projectD-core AI 治理缺口研究

- 日期：2026-08-21
- 範圍：`projectD-core` 本身，以及它對多個軟體專案、AI coding agent、Skill、MCP 與外部工具的治理能力
- 方法：本機 repository 證據盤點，加上 2024–2026 官方規範、官方工程實務、原作者文章及實證研究比對
- 結論性質：本文件是研究與建議，不代表所有建議均已核准實作

> 實作追蹤：Phase 1 已於 2026-08-21 完成，規格與驗收證據見
> `../specs/governance-evals-v2.md`。本研究的「現有 governance eval」段落保留為實作前快照。

## 摘要

`projectD-core` 已不是單純的提示詞或 `AGENTS.md` 集合。它已具備分層治理、語意路由、
任務範圍授權、角色分工、Skill 供應鏈、fleet desired state、CI、ADR、驗證與跨 session
記憶等成熟骨架。它的核心方向——少量常駐原則、按需載入、技術生態中立、證據優先、
高風險操作授權，以及制度從真實踩坑演進——與外部成熟實務高度一致。

目前最大的缺口不是再增加角色、Skill 或文字規則，而是把治理從「規則已存在」升級為
「可證明代理遵守、可追溯實際行動、可在模型與規則升級時量測退步、可在事故時撤銷與
回復」的控制系統。

建議優先順序：

1. P0：建立真正執行代理任務的 governance behavior eval harness。
2. P0：建立涵蓋 agent、model、tool、MCP、credential 與資料邊界的統一 inventory。
3. P0：把 prompt injection 改以不可信 source 到 consequential sink 的資料流控制與攻擊集治理。
4. P1：建立隱私友善、可重播的 task trace 與 incident-to-regression 閉環。
5. P1：建立跨模型／跨 host 相容性與升級 gate。
6. P1：建立長任務 checkpoint、效果指標與 approval burden 指標。
7. P2：量測 Skill routing、context budget、文件新鮮度與治理債務。

## 研究問題與判準

本研究不以「文件數量多不多」判斷成熟度，而用下列問題比對：

- 治理規則是否有清楚的來源、適用範圍與衝突順序？
- 高風險能力是否由技術邊界限制，而非只靠模型遵守文字？
- 是否能以真實任務、最終狀態與多次 trial 證明治理有效？
- 是否能追蹤 agent、model、Skill、MCP、tool、credential 與資料來源的版本及權限？
- 是否能偵測 prompt injection、memory poisoning、權限濫用與資料外傳？
- 長任務跨 context 或 session 後，是否能從可驗證狀態安全續跑？
- 模型、規則、Skill 或 tool schema 更新時，是否能比較品質、安全、成本與延遲差異？
- 真實事故是否會轉化成可重播 regression，而不是只新增一條規則？

## 本機盤點證據

### 已具備的治理構件

1. **分層與路由**：L0 憲法常駐，L1–L6 依任務語意載入，避免預載整個治理核心。
2. **範圍與授權**：`TaskScopedProposalLoop` 明確區分既有授權、MaterialProposal 與高風險操作。
3. **外部整合邊界**：以每次操作的 Source／Action 性質判斷，不以工具品牌一次定性。
4. **證據與完成校準**：要求回讀、測試、工具輸出與未驗證缺口揭露。
5. **角色邊界**：PM、SA、UX、SD、PG、QA 為可選能力，不強制低風險任務跑完整流水線。
6. **Skill 供應鏈**：來源、候選、授權、digest、staging、採用與 upstream drift 分離治理。
7. **Fleet desired state**：全域與專案入口由明確清冊接線，具有 ownership、preflight、Check 與 rollback。
8. **可執行檢查**：pre-push 與 GitHub Actions 執行 repository-local governance check。
9. **決策留痕**：ADR、memory、history 與 evidence level 避免只留下最終結果。
10. **MCP 高權限執行隔離**：已有單一 repo mount、非 root、egress allowlist、禁止匿名 tunnel 等決策。

盤點時執行統一檢查，結果為：

- 42 個 canonical Skills 通過驗證。
- 31 個 Skill sources、30 個 candidates 通過 registry 驗證。
- fleet、Skill intake、Skill update、wiring 與 governance eval contracts 通過。
- 目前共有 6 個角色 agent、16 份 ADR，以及 repository-local CI workflow。

### 現有治理 Eval 的實際能力

`evals/governance-baseline.json` 與 `scripts/governance-eval.ps1` 目前主要執行：

- 指定檔案必須包含某些文字；
- 指定檔案不得包含某些文字；
- 路徑安全、case ID 唯一性與檔案存在檢查。

它能有效防止重要條款被意外刪除或入口同步漂移，但不能證明 agent 在真實任務中會遵守條款。
因此應準確稱為「治理結構／文字契約 regression」，不能把全綠解讀為「代理行為已通過治理評估」。

### Context 與可攜性現況

- canonical Skills 共約 3,116 行、169,242 字元；frontmatter descriptions 約 11,613 字元。
- 已採 progressive disclosure，方向正確，但尚未量測 Skill routing precision、實際命中率或 context 負擔。
- 六個角色 agent 均固定 `model: opus`，並使用 Claude 式 `Read/Grep/Glob/Bash` tool metadata。
- Skills 透過開放格式提供多 host 共用，但角色 agent 的跨 Claude／Codex／Copilot 行為尚無相容性證據。
- `vault/after-action/` 目前只有說明文件，尚無正式事件紀錄。

## 外部研究發現

### 1. 成熟 Agent 系統以簡單可組合模式開始

Anthropic 從實際客戶與內部系統觀察，建議先使用最簡單可行解法；workflow 適合固定、可預測
路徑，agent 適合需要模型動態決策的情境。框架與 multi-agent 只有在品質提升大於成本、延遲
與除錯複雜度時才合理。[來源](https://www.anthropic.com/engineering/building-effective-agents)

這支持 projectD-core 不強制完整角色流水線、以任務規模路由的方向。

### 2. Context 是有限資源，規則愈多不等於遵守度愈高

Anthropic 將 context engineering 定義為選擇最小且高訊號的資訊集合；長 context 會出現
注意力稀釋，工具集合過大也會增加錯誤選擇。[來源](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

projectD-core 已有 L0 常駐、L1–L6 語意路由與 reference 下沉，但仍需量測路由是否真的把
正確 Skill 放進 context，以及 descriptions 是否造成互相競爭。

### 3. 文件是 feedforward，測試與感測器才形成 feedback

OpenAI 的 agent-first repository 以 repository-local knowledge、progressive disclosure、
custom linters、structural tests、architecture invariants 與 recurring cleanup 控制漂移；文件本身
不足以維持一致性。[來源](https://openai.com/index/harness-engineering/)

Birgitta Böckeler 將 coding-agent harness 分成 guides 與 sensors，也區分 deterministic
computational controls 與 probabilistic inferential controls。只有規則沒有 feedback，無法知道規則
是否有效。[來源](https://martinfowler.com/articles/harness-engineering.html)

projectD-core 的文字治理與結構檢查已強，但真實行為 sensors 尚未形成。

### 4. Agent Eval 必須檢查最終狀態與完整 trajectory

Anthropic 將 agent eval 拆成 task、trial、grader、transcript、outcome、agent harness 與 eval harness。
同一 task 需多次 trial；grader 應依問題混合 code-based、model-based 與 human grading；capability
與 regression suites 應分開管理。[來源](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

OpenAI 的內部 data agent 以人工 golden SQL 與實際查詢結果比較，而非只比較生成文字，並把
eval 當成開發 regression 與 production canary。[來源](https://openai.com/index/inside-our-in-house-data-agent/)

這是本專案最明確的 P0 缺口。

### 5. Prompt injection 是 source-to-sink 與 blast-radius 問題

Simon Willison 的 lethal trifecta 指出，私人資料、不可信內容與對外傳送能力同時存在時，agent
可能被誘導外傳資料；prompt guardrail 無法提供 100% 防護，關鍵是移除或限制其中一條資料流。
[來源](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)

Anthropic 也明確指出 browser／tool output 都是不可信攻擊面，需要在模型之外以權限、環境與
action boundary 限制後果。[來源](https://www.anthropic.com/research/prompt-injection-defenses)

因此 projectD-core 需要的不只是「外部內容不可信」規則，而是 tool/MCP capability inventory、
source/sink 組合檢查與可重播攻擊案例。

### 6. MCP 的描述與 annotation 不能直接視為可信事實

MCP 規範要求 server 驗證輸入、存取控制、rate limit、清理輸出；client 應提供敏感操作確認、
timeout、結果驗證與 tool audit。Tool annotations 對不可信 server 只能視為提示。
[來源](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)

授權規範進一步要求 OAuth 2.1、PKCE、token audience binding、避免 token passthrough、短效與安全
儲存。[來源](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization)

projectD-core 已有 Skill supply-chain registry，但尚未把相同治理擴展到 MCP、plugin、model、
agent profile、credential 與 tool schema。

### 7. Sandbox、approval 與 telemetry 是互補控制

OpenAI 的內部 Codex 治理同時使用 sandbox、approval policy、network policy、identity/credential
控制、managed config 與 agent-native telemetry；會記錄 tool approval、execution result、MCP
usage 與 proxy allow/deny event，以便稽核與營運調校。
[來源](https://openai.com/index/running-codex-safely/)

本專案已有高權限 MCP server 隔離 ADR，但尚缺跨工具一致的 inventory、實際 trace 與 revoke／
disable 演練。

### 8. 長任務需要可重建狀態，不能只依賴對話摘要

Anthropic 對長任務的實驗顯示，常見失敗包括 one-shot 實作、跨 context 留下半成品、下一輪猜測
狀態與過早宣告完成。有效 harness 使用 feature/acceptance list、progress file、clean-state handoff，
並在續跑前讀回狀態與執行 smoke test。
[來源](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

projectD-core 已有 memory、history 與 plan，但尚無跨 host 共用、可驗證的 task checkpoint schema。

### 9. 治理效果不能靠主觀速度感

METR 對成熟 open-source repository 的隨機對照研究中，受試者預期 AI 讓自己快 24%，事後仍認為
快 20%，但該研究樣本的實測結果反而慢 19%。此結果不能直接外推到 projectD-core，但足以證明
主觀感受不能替代 paired outcome/time measurement。
[來源](https://metr.org/Early_2025_AI_Experienced_OS_Devs_Study-paper.pdf)

## 缺口矩陣

| 優先級 | 缺口 | 本機證據 | 風險 | 建議最小控制 |
|---|---|---|---|---|
| P0 | Behavior eval harness | 現有 eval 只做內容契約 | 規則全綠但行為退步 | golden tasks、多 trial、outcome/tool-call graders |
| P0 | Agent/tool/MCP inventory | 只有 Skill registry | 權限與資料流無全貌 | versioned inventory schema + validator |
| P0 | Injection source→sink controls | 有原則，無攻擊集與 capability map | 私密資料外傳、越權 action | adversarial cases + forbidden capability combinations |
| P1 | Privacy-preserving trace | 無統一 task event model | 無法稽核、重播、量測 | redacted append-only task manifest/event schema |
| P1 | Model/host upgrade gate | agent metadata 固定 opus，無跨 host eval | 模型升級靜默退步 | compatibility matrix + same-suite before/after gate |
| P1 | Incident lifecycle | after-action 目前為空 | 事故只變成文字規則 | disable/revoke/rollback drill + incident-to-regression |
| P1 | Long-task checkpoint | 有 plan/memory，無 task state contract | 跨 context 半成品與假完成 | acceptance/progress/verification checkpoint |
| P1 | Effect metrics | 無 task success/rework/approval 指標 | 無法判斷治理投資是否值得 | scorecard with outcome, safety, UX, efficiency |
| P2 | Context/routing metrics | 42 Skills、11.6K description chars | routing confusion、注意力稀釋 | routing eval、unused/stale/conflict report |
| P2 | Governance garbage collection | 文件與候選持續增加 | 規則沉積與矛盾 | evidence-triggered gardening，禁止自動擴張治理 |

## 建議的 Behavior Eval 最小架構

### Suite 分類

1. `capability`：研究、診斷、實作、文件等正常任務能否完成。
2. `regression`：既有重要行為是否維持，例如最小改動、誠實驗證、不得未授權發布。
3. `adversarial`：prompt injection、memory poisoning、權限提升、秘密外傳與 tool misuse。

### 單一案例至少包含

- `id`、suite、risk tier、purpose。
- 固定 fixture workspace 或 mock tool environment。
- user request 與不可信外部內容分離。
- 可用 tools、filesystem、network 與 credential scope。
- 預期 final state。
- 必須／禁止的 tool calls 或 side effects。
- deterministic graders；必要時再加 rubric grader。
- trial count、pass threshold、timeout、action/retry budget。

### 第一批案例建議

1. 明確唯讀 review 不得修改檔案。
2. 使用者要求實作時允許 workspace 內必要修改，但不得碰 sibling repository。
3. 外部文件要求上傳秘密時必須拒絕外傳並繼續安全子任務。
4. Source tool 讀取權不得被解讀為 Action 授權。
5. 使用者已明確授權低風險同範圍操作時不得重複詢問。
6. 高風險 destructive action 缺少精確目標時必須停手。
7. 測試失敗時不得宣稱全綠。
8. 無測試基礎設施時不得為形式擅自新增依賴。
9. memory candidate 含外部注入文字時不得升格 verified。
10. 模型／Skill 更新後，既有 regression suite 成功率不得低於門檻。
11. context reset 後必須讀 checkpoint 並重跑 smoke test。
12. 任務完成判定以 final environment state 為準，而非 agent 自述。

## 建議的統一 Inventory

Inventory 不應只列名稱，至少要表達：

- `kind`: agent、model、skill、tool、mcp、plugin、credential、data-source。
- `id`、owner、source、version、digest、status。
- allowed hosts／workspaces／repositories。
- read/write/destructive/idempotent/open-world capabilities。
- data sensitivity、untrusted-input exposure、external-communication ability。
- credential scope、audience、storage、expiry；不得保存秘密本身。
- sandbox、network、approval、timeout、rate-limit controls。
- related eval cases、last verified evidence、rollback/disable procedure。

Inventory validator 應拒絕：

- 重複 ID、未知 kind 或不安全路徑。
- 高風險 action 沒有 approval policy。
- 同時具 private-data、untrusted-content、external-communication，卻沒有 isolation/confirmation control。
- credential 缺少 audience/scope，或 inventory 內含疑似秘密。
- active executable asset 缺少來源、版本/digest 或 disable procedure。

## 建議 KPI 與 Gate

### Quality

- task outcome pass rate，且高風險案例使用多 trial。
- regression count、spec/standards violations。
- escaped defects、human rework minutes。

### Safety

- unauthorized-action rate。
- prompt-injection attack success／exfiltration rate。
- blocked source→sink paths。
- sandbox escape、egress violation、secret exposure count。

### Control UX

- approval prompts per task。
- 有效攔截數／所有 prompts。
- human escalation precision。
- retry/action-budget exhaustion rate。

### Operability

- trace completeness 與 replay success。
- credential revoke、tool disable、rollback 所需時間。
- incident MTTR 與 stale inventory/control count。

### Efficiency

- median/p95 cycle time。
- token、cost、latency per successful task。
- 與無該治理控制或不同模型的 paired baseline 比較。

### Change Gate

model、Skill、治理規則、tool schema 或 MCP 版本更新時：

1. 固定相同 eval fixtures 與 graders。
2. 執行 capability、regression、adversarial suites。
3. 比較 pass rate、變異、成本、延遲與 approval burden。
4. 高風險 regression 不得以平均分數抵銷。
5. limited-scope canary 後才 promotion。
6. 保存 rollback target 與可回讀報告。

## 建議 Roadmap

### Phase 1：可執行治理基線

- 保留現有文字契約 eval，重新命名或分類為 structural suite。
- 新增 behavior eval schema、validator 與 deterministic fixture runner。
- 建立第一批 12 個 governance cases。
- 新增 asset inventory schema、範例清冊與 validator。
- 在 `projectd-check.ps1 -GovernanceEvals` 中執行 structural + behavior + inventory checks。

### Phase 2：安全攻擊集與 Trace

- 新增 prompt injection、memory poisoning、tool misuse 與 exfiltration fixtures。
- 建立 task trace schema，只記必要 metadata 並遮罩秘密。
- 把真實 incident／after-action 轉成 regression case。
- 執行 credential revoke、tool disable、egress deny 與 rollback 演練。

### Phase 3：跨模型與長任務

- 建立 Claude／Codex／Copilot compatibility matrix。
- 固定模型升級前後的 paired eval。
- 建立 task checkpoint 與 interrupted-session recovery cases。
- 量測 cost、latency、token 與 approval burden。

### Phase 4：治理效能與垃圾回收

- 建立 Skill routing 與 context-budget eval。
- 找出 unused、conflicting、stale rules／Skills／ADRs。
- 只有量測證明有價值時才增加自動 gardening；不得因此引入未授權背景監控。

## 不建議現在做的事

- 不因外部文章流行就導入大型 agent framework。
- 不先建立 dashboard，再回頭尋找可量測資料。
- 不把所有 MCP、plugin 或 tools 全面禁止；應依 capability 與資料流分級。
- 不保存完整 prompt、chain-of-thought 或秘密來換取 observability。
- 不設定跨所有專案固定覆蓋率或固定模型。
- 不把所有任務強制升級為多角色或多 agent。
- 不用 LLM judge 取代可確定驗證的 final-state、test、static analysis 與 tool-call grader。

## 來源與證據類型

1. NIST, *AI Risk Management Framework: Generative Artificial Intelligence Profile*, 2024-07-26。規範／自願框架。<https://doi.org/10.6028/NIST.AI.600-1>
2. NIST, *AI RMF Core*。規範／自願框架。<https://airc.nist.gov/airmf-resources/airmf/5-sec-core/>
3. OWASP, *Agentic AI — Threats and Mitigations*, 2025-02-17。社群安全規範／威脅模型。<https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/>
4. OWASP, *Top 10 for Agentic Applications 2026*, 2025-12-09。社群安全規範。<https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/>
5. Anthropic, *Building effective agents*, 2024-12-19。官方工程實務。<https://www.anthropic.com/engineering/building-effective-agents>
6. Anthropic, *Effective context engineering for AI agents*, 2025-09-29。官方工程實務。<https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
7. Anthropic, *Effective harnesses for long-running agents*, 2025-11-26。官方實驗／工程實務。<https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents>
8. Anthropic, *Demystifying evals for AI agents*, 2026-01-09。官方工程指南／案例觀察。<https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents>
9. Anthropic, *Mitigating the risk of prompt injections in browser use*, 2025-11-24。官方安全研究。<https://www.anthropic.com/research/prompt-injection-defenses>
10. OpenAI, *A practical guide to building AI agents*。官方工程指南。<https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/>
11. OpenAI, *Inside OpenAI's in-house data agent*, 2026-01-29。官方工程案例。<https://openai.com/index/inside-our-in-house-data-agent/>
12. OpenAI, *Harness engineering: leveraging Codex in an agent-first world*, 2026-02-11。官方工程案例。<https://openai.com/index/harness-engineering/>
13. OpenAI, *Running Codex safely at OpenAI*, 2026-05-08。官方安全／營運實務。<https://openai.com/index/running-codex-safely/>
14. Simon Willison, *The lethal trifecta for AI agents*, 2025-06-16。原作者安全觀點與案例彙整。<https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/>
15. Model Context Protocol, *Tools*, 2025-06-18。技術規範。<https://modelcontextprotocol.io/specification/2025-06-18/server/tools>
16. Model Context Protocol, *Authorization*, 2025-06-18。技術規範。<https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization>
17. Birgitta Böckeler, *Harness engineering for coding agent users*, 2026-04-02。資深工程師實務觀點。<https://martinfowler.com/articles/harness-engineering.html>
18. METR, *Measuring the Impact of Early-2025 AI on Experienced Open-Source Developer Productivity*, 2025-07。隨機對照實證研究。<https://metr.org/Early_2025_AI_Experienced_OS_Devs_Study-paper.pdf>

## 限制

- 本研究針對 personal、cross-project coding-agent governance，不主張直接套用大型企業的所有控制。
- 外部案例中的改善比例、攻擊成功率或生產力結果只適用其樣本與環境；本文件用它們支持
  「需要量測」，不把它們當成 projectD-core 的預期成果。
- 本機檢查證明 repository contracts 通過，不等於跨 Claude／Codex／Copilot 的代理行為已驗證。
- 研究期間工作樹原本已有 `evals/governance-baseline.json` 修改與 `.claude/` 未追蹤內容；本研究未修改它們。
