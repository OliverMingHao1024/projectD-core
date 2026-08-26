# Governance Evals v2 Phase 3 — 跨 Host 與長任務證據

- 狀態：approved / durable operation-log、Codex and Claude synchronous host-hook、adapter、paired gate、Claude run-plan integrity contracts complete / live runner、observers、pilots and cross-host matrix pending
- 核准日期：2026-08-21
- 核准內容：先實作 Codex adapter；Claude／Copilot 後續沿用同一契約
- Parent spec：`governance-evals-v2.md`

## Problem

Phase 1／2 只能證明 repository-local contracts 與 synthetic traces 通過，尚無 Claude、
Codex、Copilot 的真實執行證據，也無法比較模型升級或驗證中斷續跑。

## Outcome

建立可遮罩、可追溯、可離線評分的真實 host trial，並能比較不同 host／model、驗證
checkpoint recovery，以及量測成本與人工負擔。

## User stories

1. 維護者可以用同一批案例比較 Claude、Codex、Copilot。
2. 模型升級前後可以執行 paired trials，攔截高風險回歸。
3. 長任務中斷後可以從可驗證 checkpoint 安全續跑。
4. 維護者可以比較成功率、延遲、token、成本與 approval burden。

## Acceptance criteria

- [x] Host trace 必須包含版本、來源、runner、時間與完整性證據。
- [x] 禁止保存 raw prompt、chain-of-thought、秘密及未遮罩私人資料。
- [x] 缺少 provenance、版本或 observable final state 時 fail closed。
- [ ] Compatibility matrix 對所有 host 使用相同 fixtures 與 graders。
- [x] 高風險 regression 不得被平均分數抵銷。
- [x] Recovery 必須先讀回 checkpoint、驗證 workspace 狀態並執行 smoke test。
- [x] Recovery contract 必須從 metadata-only intent/result log 純計算 operation state，並在
  persisted/current replay policy 任一不安全時 fail closed。
- [x] Deterministic fake runner 必須覆蓋每個 action prefix 的 crash/reopen，且二次 recovery
  不得重複套用 effect。
- [x] Codex／Claude 支援的 tool path 必須在 effect 前同步落盤 intent，並於成功／失敗後以
  metadata-only result 關閉；無法落盤、identity 漂移或 record 衝突時 fail closed。
- [x] 離線 contracts 可進 CI；真實 host trials 只能經明確授權手動執行。
- [x] 無法取得的 cost／token 指標必須標示 `unavailable`，不得推估。

## Implementation decisions

- 延伸既有 task trace，另建立 host trial envelope 與 checkpoint schema。
- Host adapter 與 canonical grader 分離，避免綁定單一供應商。
- 第一個 vertical slice 先做 Codex adapter，再套用相同契約至 Claude／Copilot。
- Live trial 結果只保存必要 metadata 與遮罩後 final state。
- Repository 與 CI 只執行 deterministic contracts；live trial 必須透過獨立、手動且明確授權的入口。
- Durable operation log 與 behavior events 分離：前者只負責 recovery facts，後者繼續負責
  observable evidence 與 grader；metrics 不參與 recovery correctness。
- 第一個 operation-log slice 只涵蓋單一 run、順序 effects 與 repo-controlled fake runner，
  不導入 conversation tree、lanes、compaction/navigation 或新 storage backend。
- Live host seam 採每個 tool call 一份 operation log 與一個 bounded single-writer lock，避免
  平行 tool call 共用 session-wide pending intent；所有 live effect 的 replay 先固定為 `never`。
- Host hook 成功不輸出 allow decision，保留 host 原有 permission flow。`host-permitted` 只表示
  host 已放行該 tool call，不等於 projectD 已驗證本次 task-scoped authorization。

## Testing decisions

- 使用合法、缺 provenance、秘密洩漏、版本未知、假完成及 checkpoint 漂移 fixtures。
- 先通過 deterministic contract tests，再進行單一 host 的授權 pilot。
- Operation-log contract 在每個 manual-drive action prefix 重開，完成 recovery 後再重跑一次，
  驗證 durable records 與 idempotent effect ledger 都不再變動。
- Codex pilot 穩定後才建立三 host compatibility matrix。

## Out of scope

- 背景監控或自動執行付費模型。
- 保存完整對話或思考過程。
- 變更真實 credential、網路或正式環境。
- Dashboard 與 Phase 4 治理垃圾回收。

## Assumptions and open questions

- 第一個 adapter 使用 Codex；本階段先建立可驗證 export／validation seam，不自動啟動 Codex。
- 真實 Claude／Copilot trials 需要另行確認可用 CLI、帳號與成本邊界。
- Host 無法提供的 cost／token 欄位必須明示 `unavailable`。

## Codex／Claude 實作結果

- `governance-host-trials.schema.json`：host／model identity、provenance、source integrity、
  privacy、metrics、evaluation 與 checkpoint envelope。
- `governance-task-checkpoints.schema.json`：acceptance progress、Git commit／workspace digest、
  smoke test 與 recovery state contract。
- `codex-governance-adapter.ps1`：只接受明確授權的 metadata-only 手動匯入，讀取本機
  Codex CLI 版本與 Git state，輸出至 Git ignored 的 `.local/governance/`；不啟動模型。
- `claude-governance-adapter.ps1`：沿用同一 envelope、grader、privacy 與 checkpoint contract，
  讀取 Claude CLI 版本但不啟動模型；Claude host 不得冒用 Codex adapter identity。
- `governance-host-trial-eval.ps1`：重播既有 behavior grader、驗證來源 SHA-256、拒絕
  敏感欄位／路徑越界／reparse point，並分離 recorded checkpoint 與 current recovery gate。
- 失敗 trial 會保留為有效 evidence；high／critical regression 獨立計數，不以平均成功率抵銷。
- `safe_to_resume` 只有 canonical recovery case 通過、checkpoint 已讀、當前 workspace 與
  checkpoint 相符且 smoke test 通過時才成立。
- `governance-operation-logs.schema.json`：四種 metadata-only records（operation started、
  effect intended/result、operation finished）、runner fixed-point state 與 privacy contract。
- `governance-operation-log-eval.ps1`：唯讀 pure reducer，驗證 sequence／previous-id chain、
  intent/result pairing、authorization、replay safety、runner-state fixed point、host/checkpoint
  identity 與 current-workspace composite gate；不啟動模型或 effects。
- `governance-operation-log.contract.ps1`：fake runner 將 checkpoint write、smoke test 與
  final-state observation 拆成 10 個 gated actions；每個 prefix 均 crash/reopen、完成 recovery，
  再執行第二次 recovery 驗證 records 與 effect ledger 冪等。Current replay declaration 被移除、
  external safe replay、未授權成功、raw arguments、斷鏈與 host binding 漂移均 fail closed。
- `governance-host-operation-hook.ps1`：Codex／Claude 共用的同步 handler。PreToolUse 先以
  write-through temporary file 與 atomic replace 寫入 intent；PostToolUse／PostToolUseFailure
  只追加 metadata-only result。輸入與既有 log 有大小上限，路徑限制於 Git ignored 的
  `.local/governance/operation-hooks/`，拒絕 reparse path，並只持久化雜湊識別、分類、
  authorization basis/evidence 與 result code。
- `.codex/hooks.json` 與 `.claude/settings.json`：對各 host 可見的所有 tool path 註冊同步 hook；
  deterministic contract 驗證 pre/post、failure、duplicate delivery、input digest mismatch、
  missing stable tool ID、隱私及平行 tool call 的獨立 log。
- Live hook evidence 的 reducer 結果固定標示 `host-hook-unverified` 與
  `authorization_verified=false`；未連結具 provenance 的 host trial、checkpoint 與 current
  workspace gate 前，不能單獨令 `safe_to_resume=true`。
- Contract 已接入 `projectd-check -GovernanceEvals` 與 GitHub Actions；CI 僅使用
  `contract-fixture`，不執行真實模型或手動匯入。
- `governance-host-upgrade-gate.ps1`：離線比較兩份已驗證 host manifest；只接受相同
  evidence kind、host／harness／adapter、catalog digest、case set 與每個 case 的 trial count，
  且 run id 必須不同、model identity 必須有變更。
- 候選版只要存在 high／critical 失敗即阻擋，整體 passed count 亦不得低於 baseline；
  因此相同平均分數不能掩蓋高風險案例退步。
- duration、token、cost 與 approval count 只在兩側都有觀測值時產生 delta；缺值維持
  `unavailable`，目前不以尚未核准的效能門檻阻擋 promotion。
- `governance-host-run-plan.schema.json` 與 `claude-governance-run-plan.ps1`：paired pilot 開始前
  固定兩個不同的完整 Claude model ID、catalog／instruction／fixture digest、案例 observer、
  plan-only permission、session 不持久化、turn／timeout 與 subscription-only 零額外支出邊界。
- Run-plan validator 會拒絕浮動 model alias、來源路徑越界／reparse／digest 漂移、secret-like
  內容、未知案例、重複案例、observer 覆蓋不足、API／usage-credit fallback 或任何正數預算；
  訂閱額度耗盡時固定 stop-and-wait。Validator 只做 validation/projection，
  `live_execution` 固定為 false。

### 尚未完成

- 尚未執行任何真實 Codex pilot；目前只有 deterministic hook／operation contracts，尚未驗證
  本機 Codex runtime 是否載入 repo hook、每一條實際 tool path 的 payload 與 failure 行為。
- 尚未執行任何真實 Claude pilot；本機計畫已固定 baseline `claude-opus-4-8` 與 candidate
  `claude-opus-5`。成本邊界已固定為既有訂閱額度、零額外支出；本機
  auth status 顯示 `claude.ai` Team subscription，且未偵測到 API key／Bedrock／Vertex／Foundry。
  Observer coverage contract 已建立，但實際 filesystem／smoke-test observers 與 live runner
  尚未實作；本機 Claude runtime 是否載入 repo hook 也尚未經授權 pilot 驗證。
- Codex hosted tools（例如 WebSearch）與可能 opt out 的 specialized tool path 不在官方 hook
  coverage 內；Claude 的 `@` references 與 `EndConversation` 也不觸發 hook。這些路徑必須維持
  coverage exclusion，不得宣稱完整 durable-operation coverage。
- Codex repo hook 必須由操作員檢視並信任目前 definition hash；host hooks 被停用、project
  未受信任或設定未載入時不會執行。同一事件的其他 matching hooks 會並行啟動，其自身
  side effect 不屬於本 operation log 的 exactly-once 保證。
- 尚未建立 Copilot adapter 與三 host compatibility matrix。
- 尚未取得可供 paired gate 使用的真實 baseline／candidate Codex trial；目前只證明 gate contract。
- Model version 由手動匯入者提供並明示 `user-supplied`；本機 `codex --version` 只能證明
  匯入環境的 CLI 版本，不能獨立證明先前模型執行環境。

## References

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- `governance-evals-v2.md`
- `../research/ai-governance-gap-analysis-2026-08-21.md`
- `../history/2026-08-21-governance-evals-v2-phase-2.md`
- `../history/2026-08-22-governance-evals-v2-phase-3-codex-first.md`
