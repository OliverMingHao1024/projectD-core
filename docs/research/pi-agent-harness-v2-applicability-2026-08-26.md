# Pi Agent Harness v2 對 projectD-core 適用性研究

- 日期：2026-08-26
- 外部研究基準：`earendil-works/pi` 固定 commit
  [`f7f933c6e0a127bd2b56336338512092fec0399d`](https://github.com/earendil-works/pi/commit/f7f933c6e0a127bd2b56336338512092fec0399d)
- 本地範圍：Governance Evals v2 Phase 3 的 live runner、observer、task checkpoint 與 recovery
- 方法：外部設計文件／同 commit 原始碼與本地 schemas、validators、規格及歷程交叉比對
- 結論性質：研究與建議，不代表已核准或已實作

> 實作追蹤：使用者於 2026-08-26 指示依建議執行。最小 vertical slice 已建立
> metadata-only operation-log schema、唯讀 pure reducer/composite checkpoint gate、
> 10-action manual-drive crash-prefix contract，以及 Codex／Claude 共用的同步 PreToolUse／
> PostToolUse repo hook。真實 runner、observers 與授權 pilots 仍未完成；hook coverage exclusion
> 也不能被解讀為 Codex／Claude 已具完整 durable-operation 保證。實作狀態以
> `../specs/governance-evals-v2-phase-3.md` 為準。

## 摘要

Pi Agent Harness v2 **可以部分套用**，但應採用它的 durable-operation 設計模式與測試方法，
不應在目前階段直接把 Pi 的 `AgentHarness` runtime 或完整 session model 引入 projectD-core。

最吻合的落點是 Governance Evals v2 Phase 3 尚缺的 live runner、observer 與 checkpoint
recovery。ProjectD 已有 metadata-only append-only trace、checkpoint、current-workspace gate、
smoke-test gate 與 observable final-state grader；Harness v2 能補上的關鍵層是：

1. effect 前先持久化 intent、effect 後再持久化 result；
2. 從 durable log 純計算執行狀態的 reducer；
3. 明確的 replay safety 與中斷後人工收斂語意；
4. 把 durable records、observable events、policy hooks 與 telemetry 分開；
5. 在每個 effect boundary 模擬 crash、重開與重複 recovery。

Conversation tree、lanes、compaction、navigation、完整 JSONL／SQLite session repository 與
provider deferred-handle redemption，目前沒有足夠的 projectD 需求證據，應保留為未來觸發式
選項，不先導入。

固定 commit 的另一個重要限制是：文件描述的是完整目標設計，但當時的主要 harness runtime
尚未完成；實際 `AgentHarness` 仍有大量 public method 回傳 `HarnessNotImplemented`。此外，
相容性政策只承諾讀取舊 coding-agent v3 JSONL，其他 harness/storage API 可破壞性變更且不提供
migration。因此它適合作為設計參考，不適合作為 projectD 現階段的直接 runtime dependency。
[相容性政策](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L1-L3)
[實際 scaffold source](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/src/harness/agent-harness.ts#L347-L451)

## 證據分級

- **verified**：外部固定 commit 文件／原始碼，或本地 repository 檔案可直接支持。
- **inferred**：由外部設計與 projectD 現況比對得到的適用性判斷；不是已實作事實。
- **unknown**：目前 host 或工具未提供足夠證據，不能宣稱成立。

## Harness v2 的核心設計

### Session state 與不變量

[verified] Harness v2 將一個 session 的持久狀態拆成四類：append-only conversation tree、
named lanes、每 lane 的 chronological operation log，以及 latest-write-wins 但保留 append-only
歷史的 global facts；四者共用單調遞增 sequence。
[Session model](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L43-L60)

[verified] Conversation 與 execution state 被刻意分離。Tree 不得包含 lane state、orchestration
state 或 pointers；刪除 operation logs 仍應留下完整有效的 conversation。Entries 可被多個
lanes 共用，records 則只屬於單一 lane。
[Session invariants](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L62-L77)

[verified] 每個 lane 同時最多一個 open operation；lanes 可並行，但一個 session 仍由單一
harness writer 寫入。跨 lane writes 由 storage 的 monotonic sequence linearization 排序。
[Lane rules](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L79-L98)
[Storage contract](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L1627-L1640)

### Operation、step 與 durability

[verified] Operation 是 lane 上的 durable work unit，分為 run、compaction 與 navigation。
Operation 先 durable acceptance 再執行；已接受的 run 最後必須成為 completed、failed 或
aborted，structural operation 另可為 declined。
[Operation model](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L100-L118)

[verified] Run 由 turns 組成；turn 是 assistant step 加完整 tool batch。Step 是可重試單位，
attempt count 必須持久化並跨 restart 保留。Tool call 也是 step；parallel tools 可同時執行，
但結果依 source order 落盤。
[Run/turn/step](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L112-L118)

[verified] 最核心的 durability rule 是：effect 前先寫 intent record，預先配置 result entry ID；
effect 後使用該 ID 寫結果。Crash 留下 intent 但沒有 result 時，recovery 依 action 類型決定
complete、retry 或寫 synthetic result。設計不依賴多筆 atomic transaction。
[Durability rule](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L174-L191)

[verified] Harness 不保證 tool effect exactly-once。只有 intent 當時持久化的 replay declaration
與目前 tool declaration 都是 `safe` 時，unfinished tool 才可自動重跑；否則寫入 synthetic
`interrupted` result。Hook 自行造成的 HTTP、檔案或其他外部 side effect 同樣不在 harness 的
exactly-once 保證內，需由 hook 使用 operation ID 等方式自行做到冪等。
[Tool recovery policy](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L552-L573)
[Hook side-effect boundary](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L35-L41)

### Recovery 與 pure reducer

[verified] Restore 本身只讀、不寫入、也不啟動 effect。它以 indexed open-operation discovery、
該 operation 之後的 bounded record scan、lane 自身 entries 與必要的 point lookup 還原狀態，
不掃描整個 session 歷史。
[Restore](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L644-L689)

[verified] Live state 不是第二個事實來源，而是 operation records 與 lane-own entries 的
reduction。正常執行更新 live reduction；restore 從 storage 重算；resume 後再比較 live state
與重新 reduction 的 fixed point，不一致視為 corruption。
[Reduction contract](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L642-L689)
[Fixed-point check](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L2184-L2243)

[verified] 同 commit 的 pure reducer 已有實作，可推導 pending queues/writes、unfinished step、
deferred handle、overflow guard、terminal failure 與 effective configuration；這是該 commit
少數已真正落地的核心部分。
[Reducer source](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/src/harness/reducer.ts#L506-L667)

### Events、Hooks、Telemetry 與測試

[verified] Harness v2 將三個 channel 分開：events 是 passive、live-only、不持久化也不 replay；
hooks 是 awaited interception，可改變 execution；telemetry 是 passive process-local diagnostics。
[Events](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L1170-L1182)
[Hooks](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L1270-L1292)
[Telemetry separation](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L3093-L3101)

[verified] Manual drive 將 durable write、provider、tool、hook、timer 全部包成可逐步釋放的
effect boundary。測試可在任一 action prefix 關閉、重開、resume，並驗證每個 race 的兩種
合法順序、automatic/manual 產生相同 durable log，以及半完成 recovery 可再次執行。
[Manual drive](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L2027-L2083)
[Crash-prefix tests](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L3134-L3163)

## 固定 commit 的成熟度限制

[verified] `harness-v2.md` 的 implementation status 顯示，當時 record/reducer、部分 JSONL 與
telemetry packages 已完成，但 restore、events/hooks、lane mutation line、automatic effects、
manual gate，以及主要 run/tool/recovery runtime work packages 仍未完成。
[Implementation status](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L3241-L3423)

[verified] 實際 `AgentHarness` source 在含 records 的 session 上仍拒絕 restore，且 prompt、
compact、navigate、resume、abort、queues、watch 與 lanes 等多個公開方法仍回傳
`HarnessNotImplemented`。
[AgentHarness scaffold](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/src/harness/agent-harness.ts#L347-L451)

[verified] Pi repository 採 MIT License；若未來複製程式碼而非只採用概念，需保留 copyright
與 permission notice。
[License](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/LICENSE#L1-L20)

## projectD-core 的現有基礎與缺口

### 已有能力

[verified] Governance task trace 已要求 metadata-only privacy、單調 sequence、唯一 event ID、
previous event ID、時間與 observable final state；validator 會拒絕斷鏈、重排、重複事件與
未授權成功 action。
來源：[`../specs/governance-evals-v2.md`](../specs/governance-evals-v2.md)、
[`../../evals/schemas/governance-task-traces.schema.json`](../../evals/schemas/governance-task-traces.schema.json)、
[`../../scripts/governance-trace-eval.ps1`](../../scripts/governance-trace-eval.ps1)。

[verified] Task checkpoint 已包含 repository commit、workspace state/digest、completed/remaining
acceptance criteria、checkpoint read、workspace verification、smoke-test evidence 與
`safe_to_resume`。
來源：[`../../evals/schemas/governance-task-checkpoints.schema.json`](../../evals/schemas/governance-task-checkpoints.schema.json)。

[verified] Host-trial validator 會重新計算 recorded `safe_to_resume`，並在明確要求 current
workspace verification 時重新取得當前 commit、workspace state 與 integrity；recorded evidence
與當前狀態不符時拒絕續跑。
來源：[`../../scripts/governance-host-trial-eval.ps1`](../../scripts/governance-host-trial-eval.ps1)。

[verified] Codex／Claude adapters 目前只做明確授權的 metadata-only 手動匯入，不啟動模型、
不讀取 session/prompt/reasoning/credential；CI 只執行 deterministic contract fixtures。
來源：[`../specs/governance-evals-v2-phase-3.md`](../specs/governance-evals-v2-phase-3.md)、
[`../history/2026-08-22-governance-evals-v2-phase-3-codex-first.md`](../history/2026-08-22-governance-evals-v2-phase-3-codex-first.md)、
[`../history/2026-08-22-governance-evals-v2-phase-3-claude-adapter.md`](../history/2026-08-22-governance-evals-v2-phase-3-claude-adapter.md)。

### 尚未完成

[verified] Phase 3 尚未建立實際 tool-event、filesystem、smoke-test observers 與 live runner，
也尚未執行真實 Codex／Claude pilots、取得 paired evidence，或完成 Copilot/cross-host matrix。
來源：[`../specs/governance-evals-v2-phase-3.md`](../specs/governance-evals-v2-phase-3.md)。

[inferred] 現有 checkpoint 可以判斷一份輸入 manifest 是否聲稱且滿足安全續跑條件，但尚未
由 effect-level durable log 證明中斷前精確完成到哪一步、是否存在 intent/result window、
哪些 action 可重播，以及哪些必須人工 reconciliation。這正是 Harness v2 最適合補上的能力。

## 適用性矩陣

| Harness v2 能力 | 適用性 | projectD 建議落點 | 理由 |
|---|---|---|---|
| Intent-before-effect／result-after-effect | 高 | Phase 3 live runner operation log | 補足中斷點與 unknown-effect 證據 |
| Pure reducer | 高 | 從 log 推導 open／unfinished／interrupted／finished | 避免把 runner live state 或模型自述當權威 |
| Replay declaration／idempotency | 高 | Tool/control action policy | 高風險 action 預設不可重播 |
| Manual drive／crash-prefix tests | 高 | Fake runner 與 deterministic contracts | 可逐 effect 驗證 crash/reopen/recovery |
| Events／Hooks／Telemetry 分層 | 高但需改造 | Grader evidence／policy gate／metrics | 避免觀察、控制與診斷混為一談 |
| Per-trial single writer | 中高 | 一份 host trial 一個 writer／fenced owner | 保持 append order 與 reducer 決定性 |
| Conversation tree | 低 | 暫不導入 | ProjectD 持久產物是治理 evidence，不是 conversation repository |
| Lanes | 低 | 等 projectD 自行 orchestrate 多 thread/subagent 再評估 | 現有 host 內部 lane/writer 無法由 projectD 保證 |
| Compaction／navigation／queues | 低 | 暫不導入 | 與目前 eval/recovery tracer bullet 無直接需求 |
| JSONL／SQLite session repository | 低 | 先使用 bounded repo-local fixture／`.local` evidence | 尚無查詢效能、多 lane 或長期 session storage 證據 |
| Pi runtime/package | 不採用 | 無 | 固定 commit 尚未完成，且會綁定 Pi/TypeScript API |

## 建議採用的設計

### 1. 新增獨立 operation log，不讓 task trace 同時承擔 recovery

[inferred] Harness v2 最重要的邊界不是「所有東西都 append-only」，而是把 durable execution
records 與 conversation/events 分開。ProjectD 也應保持三層：

1. **operation records**：recovery 的唯一 durable facts；
2. **governance events/final state**：供 deterministic grader 使用的 observable evidence；
3. **metrics/telemetry**：duration、token、cost、approval burden 與 adapter diagnostics，不參與
   recovery correctness。

不建議直接擴充現有 generic behavior trial events 來同時承擔 operation reduction，以免 grader
schema、runtime state 與 privacy projection 互相綁死。

### 2. 最小 record vocabulary

[inferred] 第一個 tracer bullet 只需四種 record：

- `operation_started`
- `effect_intended`
- `effect_result`
- `operation_finished`

每筆至少含：schema version、monotonic sequence、operation ID、effect ID、前一筆 record ID、
timestamp、classification、authorization、target code、replay class 與 result code。

高風險或外部 effect 中斷後，若無法從 observable state 確認結果，不得推定未執行或成功；
reducer 應產生 `interrupted`／`unknown-external-effect`，要求 query-before-retry 或人工收斂。

### 3. Privacy-preserving adaptation

[verified] Pi 的 `ToolStartedRecord` 會持久化 hook 後的 `effectiveArgs`，而 projectD 的 canonical
trace 明確禁止 raw prompt、chain-of-thought、secret values 與未遮罩 private data。
[Pi tool record](https://github.com/earendil-works/pi/blob/f7f933c6e0a127bd2b56336338512092fec0399d/packages/agent/docs/harness-v2.md#L246-L261)
來源：[`../../evals/schemas/governance-task-traces.schema.json`](../../evals/schemas/governance-task-traces.schema.json)。

[inferred] ProjectD 不應複製 `effectiveArgs`。Durable evidence 應只保存 allowlisted metadata、
argument digest、target code 與 safety classification。若某個 effect 必須靠完整參數才能 crash-safe
重播，應使用受控、可重建的 operation definition 或另行設計安全儲存；在此之前 replay 預設
`never`。

### 4. Host capability boundary

[inferred] 完整 Harness v2 保證要求 provider、tool、hook、timer 與 durable write 都穿過 injected
effects boundary。若 Codex／Claude 是黑箱 CLI，只能在 action 完成後輸出 event，projectD 就
不能宣稱 intent-before-effect 或 deterministic manual stepping。

Host adapter 因此應明確標示 capability：

- `pre_effect_interception`：是否能在 effect 前持久化 intent；
- `post_effect_observation`：是否只能事後觀察；
- `cancellation_observable`：是否能分辨 cancelled 與 unknown；
- `tool_identity_stable`：是否有可跨 restart 關聯的 tool/action ID。

只有 `pre_effect_interception=true` 且 durable intent 實際落盤的路徑，才能主張 durable-operation
coverage。其他路徑只能標示 `observed-after-effect`，並保留 coverage exclusion。

[verified, 2026-08-26] Codex 官方 hooks 提供同步 `PreToolUse`／`PostToolUse`，pre hook 可在 tool
執行前以 exit 2 阻擋；但 hosted tools（例如 WebSearch）不在 hook coverage，部分 specialized
tool path 也可能 opt out。Claude Code 同樣提供同步 `PreToolUse`、`PostToolUse` 與
`PostToolUseFailure`，pre hook exit 2 可阻擋 tool；`@` references 與 `EndConversation` 不受 hook
涵蓋。來源：[Codex hooks](https://learn.chatgpt.com/docs/hooks)、
[Claude Code hooks](https://code.claude.com/docs/en/hooks)。

[verified, local] projectD 已以 `.codex/hooks.json`、`.claude/settings.json` 將各 host 可見的 tool
事件接到共用 `governance-host-operation-hook.ps1`。Handler 在 pre 階段先 durable write intent，
post 階段再寫 result；每個 tool identity 使用獨立 log／lock，raw arguments、output 與 error
不持久化。Deterministic contract 只證明 handler 與 config 契約，不證明 live host 已載入、所有
tool path 均被攔截或 task-scoped authorization 已獲驗證。

## 最小 tracer bullet

建議用既有 high-risk case `interrupted-task-reads-checkpoint-before-resume`，先選單一 host，依序：

1. 定義 provider-neutral operation-log schema，不修改 conversation/session 模型。
2. 建立 pure reducer，從 log 推導 `open`、`unfinished`、`interrupted`、`completed`、`failed`。
3. Fake runner 將 projectD 自己控制的 durable writes、checkpoint write、smoke test 與 final-state
   observation 放入 manual gate。
4. 在每個 action prefix 關閉 runner、重開、執行 recovery；同一 prefix 再 recovery 第二次，
   證明冪等。
5. 所有 effect 的 replay 預設 `never`；只有 repo-local、無外部 side effect 且可證明冪等者才
   可標 `safe`。
6. Resume 前沿用既有 checkpoint read、current-workspace commit/state/digest 驗證與 smoke test。
7. Resume 或 finish 後重新 reduction，與 runner live state 做 fixed-point 比對；不一致 fail closed。
8. 將 reduction 結果投影成現有 behavior-trial events／final state，再交既有 grader 判分。
9. Deterministic contracts 通過後，才評估一個經使用者明確授權的 live host pilot。

## 建議驗收條件

1. Operation log schema 拒絕 sequence 斷裂、重複 ID、未知 operation、finish 後新增 operation record、
   result 沒有對應 intent，以及 provisioned result identity 不一致。
2. Restore/reducer 為 pure read；不寫檔、不啟動模型、不執行 tool 或 smoke test。
3. 每個已接受 operation 恰有一個 terminal record，或明確維持 suspended/open。
4. 每個 external/high-risk effect 都有 replay class；缺失時 fail closed。
5. `safe` replay 需同時滿足 persisted 與 current declaration；任一側不是 `safe` 就不得自動重跑。
6. 每個 durable boundary 都有 crash/reopen/recovery fixture，並對同一 prefix 執行兩次 recovery。
7. Recorded checkpoint、current workspace、smoke test 與 reducer state 任何一項不符時，
   `safe_to_resume=false`。
8. 持久 evidence 維持 metadata-only，無 raw prompt、reasoning、tool args/output、秘密或私人資料。
9. Opaque host 無 pre-effect seam 時，輸出明確 coverage exclusion，不得宣稱完整 durable-operation
   coverage。
10. 現有 behavior grader、host-trial validator、upgrade gate 與 repository checks 維持通過。

## 目前不採用與重新評估觸發條件

### Conversation tree／lanes

目前不採用。只有下列任一實際需求出現時重新評估：

- ProjectD 開始自行 orchestrate 同一 session 的多 thread/subagent；
- 需要共享 conversation prefix 並在多分支間導航；
- 同一 durable session 需要並行但隔離的 operation ownership。

### JSONL／SQLite session repository

目前不採用。只有下列任一證據出現時重新評估：

- operation log 已大到 bounded file scan 無法滿足；
- 需要多 lane indexed query；
- crash-safe append 或 concurrent writer contention 已成為真實問題；
- 需要跨大量 sessions 查詢 open operations。

### Pi runtime dependency

目前不採用。若未來再評估，至少要求：

- 上游主要 harness runtime work packages 已完成；
- public API 與 storage format 有可接受的 version/migration policy；
- 能以 provider-neutral adapter 整合 Codex／Claude／Copilot，而不是把 projectD canonical schema
  綁定 Pi types；
- 完成 license notice、供應鏈、安全、相容性與維護成本審查。

## 最終建議

[inferred] **採用 Harness v2 的四個核心模式：operation intent/result log、pure reducer、replay
safety、action-prefix crash testing。** 將它們視為 Governance Evals v2 Phase 3 live runner 的
設計輸入，不視為新 framework 或 runtime dependency。

[inferred] 第一階段只包裝 projectD 自己控制的 effects，對黑箱 host 保持誠實 coverage
exclusion。若單一 recovery tracer bullet 證明這套模型確實能捕捉現有 checkpoint 無法表示的
中斷狀態，再依實際需要擴充 record vocabulary、host interception 或 storage；在此之前不導入
lanes、conversation tree、compaction/navigation 或 SQLite。

這個取捨符合 projectD-core 的最小必要改動、證據優先、技術生態中立、驗證誠實，以及制度只
從真實需求演進的既有原則。
