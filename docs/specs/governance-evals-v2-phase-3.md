# Governance Evals v2 Phase 3 — 跨 Host 與長任務證據

- 狀態：approved；durable operation log、Codex／Claude hooks、adapters、run-plan integrity 與 paired upgrade gate complete；2026-09-04 current-policy Codex 與 Claude single-host bounded authorization revalidation verified；live runner、observers、broader pilots、Copilot 與 cross-host matrix pending
- 核准日期：2026-08-21
- Parent：[`governance-evals-v2.md`](governance-evals-v2.md)
- 完整採用與實作歷程：[projectD-knowledge archive](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/design/governance-evals-v2-phase-3-full-history.md)

## 目標與權威邊界

Phase 3 建立可遮罩、可追溯、可離線評分的 host trial，支援 host／model 比較、升級回歸阻擋、
checkpoint recovery、token／cost／latency／approval burden 報告。

Repository 與 CI 只執行 deterministic contracts。真實 host trials、模型呼叫與任何可能產生成本或
接觸 credential／外部系統的動作，必須經明確授權的手動入口；未取得 live evidence 前不得宣稱
runtime、hook coverage 或跨 host compatibility 已驗證。

## Runtime Governance v2 關係

Phase 3 的 durable operation log、checkpoint、host trial 與 upgrade gate 繼續作為 evidence/recovery contracts。Runtime capability classification 與 task-scoped authorization 的新權威邊界改由 [`agent-runtime-governance.md`](agent-runtime-governance.md) 與 `evals/schemas/governance-runtime-policy-decisions.schema.json` 表達。

既有 operation-log `classification` 欄位保留相容性，不再視為完整 runtime authorization taxonomy。Host hook 現在先以 Runtime Governance v2 normalizer 產生 capability/effect decision，再投影成 legacy operation-log classification；只有 payload 無法提供足夠語意時才使用 tool-name fallback 或 `unclassified-effect`。Local/network read 維持 advisory observe-only，且不會因不相關 envelope 升格成 verified authorization；effectful／unclassified operation 沒有 task envelope 時會 pre-effect enforced deny，有 validated、unexpired、current-policy task envelope 與 matching grant 時才 deterministic allow。對 verified v2 allow，legacy operation evidence 也投影成 `explicit-current-task`／`authorized=true`，避免與 runtime decision 出現相反授權語意；advisory read 仍保留 `host-hook-policy`／`host-policy-pending`。2026-09-03 trusted interactive Codex CLI `0.152.1`／Windows pilot 已在同一 task/run identity 下驗證 bounded metadata bootstrap、built-in `apply_patch` 的 `workspace-write` enforced allow，以及未授權 shell `command-execute` 的 pre-effect enforced deny；decision、authorization、operation evidence 與 metadata-only privacy checks 均通過。其後 host hook 新增 verified v2 allow → legacy `explicit-current-task / authorized=true` 的一致性投影；2026-09-04 已針對更新後 policy bundle digest `sha256:56c7cc9e5b197627681cf6aaae82cefbe6462823de812187681b1c1dbd100107` 完成同樣 bounded Codex revalidation，bootstrap、workspace allow、legacy authorization projection、pre-effect shell deny 與 metadata-only evidence 均通過；同一 policy bundle 也完成 Claude bounded single-host revalidation。這些 evidence 仍不能外推到其他 Codex／Claude model、其他 tool path、recovery 或不可觀測路徑。

## Host evidence 契約

- Host trial 必須記錄 host／model／runner／adapter 版本、來源 provenance、時間、source integrity、
  observable final state、privacy state、metrics 與 checkpoint envelope。
- 禁止保存 raw prompt、chain-of-thought、秘密、tool arguments／outputs 或未遮罩私人資料。
- 缺 provenance、版本、完整性或 final state 時 fail closed。
- 無法取得的 token、cost 或其他 metrics 必須標為 `unavailable`，不得填 0 或推估。
- High／critical regression 獨立阻擋，不得被平均通過率抵銷。
- Compatibility matrix 必須讓各 host 使用相同 fixtures 與 graders。

## Recovery 與 operation log 契約

- Recovery 前必須讀回 checkpoint、驗證 workspace identity／digest 並通過 smoke test。
- Operation log 與 behavior events 分離；前者記錄 recovery facts，後者提供 observable evidence。
- Log 只允許 metadata-only 的 operation-started、effect-intended、effect-result、operation-finished records。
- Intent 必須在 effect 前同步 durable write；result 必須在成功或失敗後關閉 intent。
- Sequence／previous-ID chain、authorization、host/checkpoint identity、persisted/current replay policy、
  runner fixed point 或 workspace gate 任一不安全時 fail closed。
- 每個 tool call 使用獨立 operation log 與 bounded single-writer lock；live effect replay 固定為 `never`。
- Fake runner 必須涵蓋每個 action prefix 的 crash/reopen；第二次 recovery 不得重複 effect。

## Host hook 邊界

- `scripts/governance-host-operation-hook.ps1` 是 Codex／Claude 共用同步 handler。
- PreToolUse 使用 write-through temporary file 與 atomic replace 先寫 intent；PostToolUse／Failure 只追加 result。
- `.codex/hooks.json` 與 `.claude/settings.json` 註冊各 host 可見的 tool paths。
- Hook 成功不輸出 allow decision，保留 host 原有 permission flow。Codex deny 以正常 exit 0 回傳 structured `PreToolUse permissionDecision=deny`；Claude deny 維持 stderr 加 exit 2。
- `host-permitted` 不等於 projectD 已驗證 task-scoped authorization；只有 v2 verified allow 才能在 legacy log 投影成 `explicit-current-task`。
- 單獨的 hook evidence 固定為 `host-hook-unverified`、`authorization_verified=false`，不得令
  `safe_to_resume=true`。

## Canonical assets

- Host trial／checkpoint／operation-log／run-plan schemas：`evals/schemas/governance-*.schema.json`
- Host adapters：`scripts/codex-governance-adapter.ps1`、`scripts/claude-governance-adapter.ps1`
- Trial／operation evaluators：`scripts/governance-host-trial-eval.ps1`、
  `scripts/governance-operation-log-eval.ps1`
- Hook：`scripts/governance-host-operation-hook.ps1`
- Upgrade gate：`scripts/governance-host-upgrade-gate.ps1`
- Claude run plan：`scripts/claude-governance-run-plan.ps1`
- Contracts：`scripts/tests/governance-*.contract.ps1`

## Paired upgrade gate

Baseline 與 candidate 必須是不同 run、不同完整 model identity，但具有相同 evidence kind、host、
harness、adapter、catalog digest、case set 與每 case trial count。Candidate 有任何 high／critical failure，
或總 passed count 低於 baseline，即阻擋 promotion。Metrics 只有兩側皆 observed 才計算 delta。

## 未完成邊界

- Codex current-policy 已完成 bounded same-session runtime hook loading、task authorization、workspace-write allow、legacy authorization projection 與 command-execute pre-effect deny；Claude current-policy 也已完成 built-in Read bootstrap、Write allow、legacy authorization projection 與 Bash command-execute pre-effect deny。2026-09-04 revalidation 是兩個 host 的現行 bounded live authorization evidence。2026-09-03 與 2026-09-02 的舊 digest evidence 保留為歷史比較／Windows transport 證據。其他 capability/tool path、failure payload matrix 與 cross-host recovery 仍未完成。
- 尚未完成 filesystem／smoke-test live observers 與 live runner。
- Copilot adapter、三 host compatibility matrix 與授權 paired evidence 尚未完成。
- Hosted／specialized tool paths 未被官方 hooks 覆蓋時，必須明示 coverage exclusion。

## 現行驗證

```powershell
pwsh -NoProfile -File scripts/projectd-check.ps1 -SkipGlobal -GovernanceEvals
pwsh -NoProfile -File scripts/tests/governance-operation-log.contract.ps1
pwsh -NoProfile -File scripts/tests/governance-host-operation-hook.contract.ps1
```
