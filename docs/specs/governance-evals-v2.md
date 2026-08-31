# Governance Evals v2

- 狀態：approved / Phase 1 complete / Phase 2 complete / Phase 3 durable operation log and Codex-Claude hook contracts, adapters, run-plan integrity and upgrade gate complete
- 核准日期：2026-08-21
- Phase 2 核准：2026-08-21（使用者指示「繼續」）
- 研究依據：`https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/research/projectd-core/ai-governance-gap-analysis-2026-08-21.md`
- 採用歷程：`https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/history/governance-evals/2026-08-21-governance-evals-v2-phase-1.md`、
  `https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/history/governance-evals/2026-08-21-governance-evals-v2-phase-2.md`
- Phase 3 規格：`governance-evals-v2-phase-3.md`

## Roadmap 狀態

| 階段 | 狀態 | 邊界 |
|---|---|---|
| Phase 1 | complete | Provider-neutral behavior catalog、asset inventory、deterministic grader 與 CI wiring。 |
| Phase 2 | complete | Metadata-only synthetic security traces、control drills 與 verified incident intake contract。 |
| Phase 3 | in progress | Codex／Claude host trial adapters、checkpoint contract、durable operation-log schema／pure reducer／manual-drive crash contract、repo-local synchronous PreToolUse/PostToolUse hook seam、Claude paired-pilot run-plan integrity 與 paired upgrade gate 已完成；真實 runner／observers、授權 pilots／paired evidence、Copilot 與 cross-host matrix 待後續切片。 |
| Phase 4 | not started | Skill routing、context budget、治理資產 stale／conflict 偵測與 evidence-driven gardening。 |

Phase 1／2 的完成證據只涵蓋 repository-local contracts 與 synthetic fixtures；任何真實模型、
host runtime、credential、MCP process、sandbox、approval 或 egress 狀態，必須取得 Phase 3
結構化 trial evidence 後才能宣稱已驗證。

## 目標

在不綁定模型供應商、不呼叫付費 API，也不保存完整 prompt 或秘密的前提下，建立：

1. 可描述真實 agent trial、tool call 與 final state 的 behavior eval contract。
2. 可離線重播及判分 trial trace 的 deterministic grader。
3. 涵蓋 agent、model、Skill catalog、tool、MCP、plugin、credential 與 data source 的 inventory contract。
4. prompt injection、memory poisoning、越權、秘密外傳與 Source→Action 邊界案例。
5. `projectd-check.ps1 -GovernanceEvals` 與 CI 整合。

## Phase 1 邊界

Phase 1 只建立 provider-neutral contract、catalog、validator、grader 與 contract fixtures。
它不啟動 Claude、Codex 或 Copilot，也不宣稱 canonical catalog 已被任何真實模型通過。
真實 host adapter、跨模型 paired trials、task trace persistence 與 dashboard 留待後續 phase。

Inventory 只涵蓋 repository 可驗證的 canonical assets。Host runtime 動態提供的 tools、MCP、
plugins、models 與 credentials 必須由 host/project inventory 補充；canonical inventory 需明列
coverage exclusion，不得把未知資產靜默視為已治理。

Secret-like value detection 只攔截禁止欄位與常見 credential/private-key markers，不是通用
secret scanner，也不能證明任意字串不含敏感資料。Host adapter 必須先做資料最小化與遮罩，
grader 只接受結構化 trace。Inventory validator 驗證聲明、路徑、digest 與必要控制是否完整，
不證明 host 在 runtime 已落實 sandbox、network 或 approval policy；真實行為仍需 trial evidence。

## Behavior eval contract

每個 case 包含：

- 唯一 `id`、suite、risk tier、purpose。
- `minimum_trials` 與 `pass_threshold`。
- 對 outcome、final state、required events、forbidden events 與 action budget 的期待。

每個 trial 包含：

- `case_id`、唯一 `trial_id`、agent/model/harness metadata。
- 結構化 events；不得包含完整 prompt、chain-of-thought 或秘密。
- outcome 與 final state。

Grader 比對 observable state 與 tool events，不接受 agent 的成功宣告取代 final-state evidence。

## Inventory contract

每個 asset 至少包含：

- identity、kind、owner、status 與 risk tier。
- source/version/integrity evidence。
- read/write/destructive/open-world、private-data、untrusted-content、external-communication capabilities。
- approval、isolation、disable/rollback controls。
- 對應 eval case。

Validator 必須 fail closed：

- active 高風險資產沒有 approval 或 disable procedure。
- active executable asset 缺少 integrity evidence。
- private data、untrusted content、external communication 三者同時存在卻沒有 source/sink policy。
- credential 包含 secret/token/password/value 欄位，或缺少 scope/audience/storage/expiry policy。
- repository-local source 路徑越界或不存在。
- related eval case 不存在。

Repository-local text executable 的 integrity 使用 UTF-8、LF canonical bytes 計算
SHA-256；CRLF／LF checkout 差異不得被誤判為內容遭修改，其他字元變更仍必須失敗。

## 驗收條件

1. Canonical behavior catalog 至少包含 12 個案例並通過 catalog validation。
2. 合法 trial fixture 通過；越權、外傳或虛假完成 trial 以非零 exit code 失敗。
3. Canonical inventory 通過；lethal-trifecta、缺 disable control、內嵌秘密與未知 eval fixture 失敗。
4. `projectd-check.ps1 -GovernanceEvals` 分別回報 structural、behavior catalog、asset inventory。
5. 既有 unified checks 與 contract tests 維持全綠。
6. 完成 security-review 與 Standards／Spec code-review gate。

## Phase 2 — 安全攻擊集與 Trace

### 目標

在 Phase 1 contract 上加入可離線重播、隱私友善的 task trace，證明 eval harness
能判斷四類攻擊與四項控制演練，而不是只確認案例名稱存在。

### 邊界

- canonical trace 使用 synthetic fixture，不啟動真實 agent、不存 raw prompt、
  chain-of-thought、秘密或私人資料。
- Phase 2 validator 不接受 `host-captured` 標籤；必須等授權 host adapter、provenance
  與 integrity contract 建立後才能開放，避免任意 fixture 冒充真實執行證據。
- trace 只保存 pseudonymous task reference、host/model/harness alias、時間、事件類型、
  授權／外部／破壞性旗標、控制結果與 observable final state。
- event 以單調 sequence、唯一 event id 與 previous event id 形成 append-only chain；
  validator 必須拒絕斷鏈、重排或重複事件。
- 真實 incident 只有在既有 after-action 具 `verified` 證據時才能標為
  incident-derived。沒有真實事件時使用明示的 coverage exclusion，不得偽造事故。
- credential revoke、tool disable、egress deny 與 rollback 僅操作 fixture state；
  Phase 2 不碰真實 credential、host tool 或網路設定。

### 驗收條件

1. Task trace schema 與 validator 拒絕 forbidden fields、secret-like values、事件斷鏈、
   未授權成功 action 與缺少 observable final state。
2. Canonical suite 至少各包含 prompt injection、memory poisoning、tool misuse、
   exfiltration 一個攻擊 trace，且安全結果可重播通過。
3. Canonical suite 至少各包含 credential revoke、tool disable、egress deny、rollback
   一個 drill，且 validator 驗證必要 control event 與 final state。
4. after-action regression mapping 必須引用同一文件內 trace 與既有 behavior case；
   synthetic drill 不得宣稱為 verified incident。
5. `projectd-check.ps1 -GovernanceEvals` 與 CI 獨立回報 trace replay contract。
6. focused contracts、既有相關 suite、security-review 與 code-review gate 全數通過。

### Phase 2 實作與驗證結果

- 8 個 metadata-only canonical traces：四類攻擊與四項控制演練各一個。
- append-only event chain、action budget、事件時間界線、未授權成功 action、秘密欄位／
  marker 與 observable final state 均由 deterministic validator 驗證。
- after-action regression 目前只有一個明示為 `simulated` 的 rollback mapping；因尚無人工接受的
  verified incident，保留 `no-verified-incidents` exclusion，未偽造事故紀錄。
- verified incident intake 只接受 `vault/after-action/YYYY-MM-DD-*.md` 下存在、非 reparse、
  小於 1 MiB 且 frontmatter 唯一標示 accepted／verified／matching incident id 的證據。
- trace 輸入上限 10 MiB、每個 trace 最多 1024 events；canonical suite 最多 1000 traces。
- `host-captured` 在 Phase 2 fail closed；待授權 adapter 與 provenance contract 存在後再開放。
- `projectd-check.ps1 -SkipGlobal -GovernanceEvals`：12 passed、0 failed。
- PowerShell focused／repository contracts 與參數化 GovernanceWiring fixture：通過。
- Python 純 `unittest`：3 passed；完整 discovery 因本機未安裝既有測試所需 pytest 而未執行，
  未為形式新增依賴。
- Security review：2 項 findings 修正後 focused re-review 通過。
- Standards／Spec code-review：Material finding 修正後 focused re-review 通過；保留一項非阻斷
  Minor（Phase 1／2 secret marker 掃描邏輯重複）作為有實際漂移證據時的重構候選。
