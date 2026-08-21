---
project: projectD-core
date: 2026-08-21
type: architecture
status: accepted
evidence_level: verified
technologies: [PowerShell, JSON Schema, GitHub Actions]
commits: [932f50e]
supersedes: []
verified_by:
  - "user-confirmed continue decision"
  - "projectd-check -SkipGlobal -GovernanceEvals: 12/12 checks passed"
  - "focused PowerShell governance contracts passed"
  - "Python unittest: 3 passed"
  - "security review: passed after remediation"
  - "code review: passed after remediation"
---

# 採用 Governance Evals v2 Phase 2

## Context

[verified] Phase 1 已建立 provider-neutral behavior catalog、repository asset inventory、
deterministic offline grader 與 CI wiring，但尚未用可重播 trace 證明 harness 能判斷
prompt injection、memory poisoning、tool misuse、exfiltration 與控制演練結果。

[user-confirmed] Phase 1 完成後，使用者於 2026-08-21 指示「繼續」，授權實作 Phase 2
安全攻擊集與隱私友善 Trace。

## Goal

在不啟動真實 agent、不讀取真實 credential、不改動 host tool 或網路設定的前提下，建立
可離線重播、可驗證完整性且不保存 raw prompt、chain-of-thought、秘密或私人資料的 task trace。

## Decision

正式採用 Governance Evals v2 Phase 2：

1. 使用 metadata-only synthetic traces，分別覆蓋 prompt injection、memory poisoning、
   tool misuse、exfiltration，以及 credential revoke、tool disable、egress deny、rollback。
2. 以單調 sequence、唯一 event id 與 previous event id 建立 append-only event chain；
   validator 對斷鏈、重排、重複事件、超出 action budget 與缺少 observable final state fail closed。
3. trace 僅保存 pseudonymous task reference、host/model/harness alias、時間、事件類型、
   授權／外部／破壞性旗標、控制結果與 observable final state。
4. `host-captured` trace 在 Phase 2 明確拒絕；未建立授權 adapter、provenance 與 integrity
   contract 前，不允許 synthetic fixture 冒充真實執行證據。
5. incident-derived regression 只接受 repository 內 accepted、verified 且 incident id 相符的
   after-action；目前沒有合格真實事故，因此保留 `no-verified-incidents` coverage exclusion。

## Resolution

[verified] Phase 2 已完成：

- `evals/governance-security-traces.json`：8 個 canonical traces，四類攻擊與四項控制演練各一個。
- `evals/schemas/governance-task-traces.schema.json`：task trace schema。
- `scripts/governance-trace-eval.ps1`：deterministic trace validator／replay grader。
- `scripts/tests/governance-trace-eval.contract.ps1`：合法與失敗情境 contract coverage。
- `vault/after-action/README.md`：verified incident intake contract。
- `scripts/projectd-check.ps1` 與 GitHub Actions：獨立回報 governance security trace check。

after-action regression mapping 目前只有一個明示為 `simulated` 的 rollback mapping，沒有把
synthetic drill 誤標為真實事故。Trace 輸入限制為 10 MiB、單一 trace 最多 1024 events、
canonical suite 最多 1000 traces。

## Verification

- `scripts/projectd-check.ps1 -SkipGlobal -GovernanceEvals`：12 passed、0 failed。
- focused PowerShell contracts、repository contracts 與參數化 GovernanceWiring fixture：通過。
- Python `unittest`：3 passed。
- 完整 `pytest` discovery 未執行，因本機未安裝既有測試所需 pytest；未為形式新增依賴。
- Security review 的兩項 material findings 修正後，focused re-review 通過。
- Standards／Spec code review 的 material finding 修正後，focused re-review 通過。
- 保留一項非阻斷 minor：Phase 1／2 secret marker 掃描邏輯重複；等出現實際漂移證據再重構。

## Known limitations

- 全綠只證明 repository-local contracts 與 synthetic traces 通過，不代表 Claude、Codex、
  Copilot 或任何真實模型已通過治理評估。
- Host runtime 的精確 model version、credential、MCP process、sandbox、approval 與 network
  egress 仍屬 coverage exclusion。
- 尚未建立多次 trial、跨 host compatibility matrix、模型升級 paired gate、task checkpoint
  recovery，以及 cost、latency、token、approval burden 指標。

## Next boundary

Phase 3 才處理授權 host adapter、host-captured provenance、跨 Claude／Codex／Copilot 的
相容性與升級比較、長任務 checkpoint／中斷復原及效果量測。這些工作不得因 Phase 2
完成而視為已授權或已驗證。
