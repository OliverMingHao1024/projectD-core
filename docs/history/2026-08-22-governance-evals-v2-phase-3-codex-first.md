---
project: projectD-core
date: 2026-08-22
type: architecture
status: accepted
evidence_level: verified
technologies: [PowerShell, JSON Schema, GitHub Actions]
commits: []
supersedes: []
verified_by:
  - "user-approved Phase 3 draft and Codex-first implementation"
  - "governance host-trial contract passed"
  - "governance host upgrade-gate contract passed"
  - "projectd-check -SkipGlobal -GovernanceEvals passed"
  - "security review passed after focused remediation"
  - "Standards/Spec code review passed after focused remediation"
---

# 採用 Governance Evals v2 Phase 3 Codex-first Contract Slice

## Context

[verified] Phase 1／2 已能驗證 repository-local behavior contracts、asset inventory 與
synthetic security traces，但沒有 host provenance、模型／CLI 版本、來源 integrity、task
checkpoint 或 current-workspace recovery gate。

[user-confirmed] 使用者於 2026-08-21 核准 Phase 3 規格，指定先實作 Codex adapter。

## Decision

採用 Codex-first 最小垂直切片：

1. 建立 host trial envelope 與 task checkpoint schemas。
2. 建立 Codex metadata-only 手動匯入 adapter；adapter 不啟動模型、不讀取 session、prompt、
   chain-of-thought 或 credential，且只輸出至 Git ignored 的 `.local/governance/`。
3. 手動匯入必須明確使用 `AuthorizedManualImport`；CI 只允許明示的 `ContractFixture`。
4. Model version 使用者提供時標記為 `user-supplied`；本機 `codex --version` 只證明匯入環境，
   不宣稱能獨立證明先前模型執行環境。
5. 來源 trials 與 catalog 保留 repository-relative reference 與 SHA-256，並重用 Phase 1
   behavior grader，不另寫一套 outcome 評分邏輯。
6. 通過與失敗 trials 都保存；high／critical regressions 獨立計數。
7. `safe_to_resume` 必須同時滿足 canonical recovery case 通過、checkpoint 已讀、current
   workspace commit／state digest 相符及 smoke test 通過。
8. Paired promotion gate 必須先分別驗證 baseline／candidate manifest，固定 evidence kind、
   host／harness／adapter、catalog digest、case set 與每個 case 的 trial count；候選版
   high／critical 失敗一律阻擋，passed count 亦不得下降。
9. 效能 delta 只比較雙方都有的觀測值；`unavailable` 不推估、不冒充實測，也不在尚未
   核准門檻前自行阻擋 promotion。

## Resolution

[verified] Codex-first contract slice 已完成：

- `evals/schemas/governance-host-trials.schema.json`
- `evals/schemas/governance-task-checkpoints.schema.json`
- `scripts/codex-governance-adapter.ps1`
- `scripts/governance-host-trial-eval.ps1`
- `scripts/tests/governance-host-trial.contract.ps1`
- `scripts/governance-host-upgrade-gate.ps1`
- `scripts/tests/governance-host-upgrade-gate.contract.ps1`
- `scripts/projectd-check.ps1` 與 GitHub Actions wiring
- `evals/governance-assets.json` 的三項 Phase 3 tool inventory

## Review findings and remediation

- Security review Material：歷史 checkpoint 未驗證 current workspace 仍可能顯示可續跑；
  修正為未執行 current recovery check 時一律不對外授權 resume。
- Security review Material：只接受全綠 trials 會遺失模型回歸證據；修正為失敗 trials 仍是
  valid evidence，並獨立計數 high／critical regressions。
- Code review Spec Material：任意全綠 catalog 可能產生可續跑 checkpoint；修正為 canonical
  `interrupted-task-reads-checkpoint-before-resume` 必須存在且通過。
- Upgrade-gate security review Material：來源 trials 的 schema／harness 失敗可能被誤讀為
  `0` 個 high-risk regression；修正為 behavior input contract 失敗即拒絕整份 host evidence。
- Upgrade-gate Spec review Material：相同 catalog 但每個 case 的 trial 次數不同仍可能被視為
  paired；修正為逐 case trial count 必須完全一致。
- Standards 軸保留一項非阻斷 Minor：adapter 與 validator 的 bounded path、hash、process
  helpers 有重複；待出現實際漂移證據再抽共用模組，避免本階段擴張重構。

## Verification

- Host-trial focused contract：通過。
- Host upgrade-gate focused contract：通過；相同總通過數但 critical 案例退步、無效來源
  contract 或逐 case trial count 不同都會被阻擋。
- Governance asset inventory：15 assets valid。
- `projectd-check -SkipFleet -SkipGlobal -SkipWiring -GovernanceEvals`：14 passed、0 failed。
- 九組 PowerShell contracts：在各自必要參數下通過。
- Python 純 `unittest`：3 passed。
- 完整 Python discovery 未通過，因既有 `test_governance_wiring_contract.py` 需要本機未安裝的
  pytest；未為此切片新增依賴。
- `git diff --check`：通過。
- Focused security re-review 與 Standards／Spec code re-review：通過。

## Remaining boundary

- 尚未執行真實 Codex pilot；現有證據是 deterministic contract fixture。
- 尚未建立 Claude／Copilot adapters 或 compatibility matrix。
- 尚未取得真實 baseline／candidate Codex evidence；現有 paired gate 證據是 deterministic contract fixture。
- 尚未完成跨 host cost、latency、token 與 approval burden 的實際比較。

因此 Phase 3 整體維持 in progress，不因 Codex-first contract slice 完成而宣稱跨 host 治理已完成。
