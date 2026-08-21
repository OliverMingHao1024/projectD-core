---
project: projectD-core
date: 2026-08-21
type: architecture
status: accepted
evidence_level: verified
technologies: [PowerShell, Python, JSON Schema, GitHub Actions]
commits: []
supersedes: []
verified_by:
  - "user-confirmed retain decision"
  - "six PowerShell governance contracts passed"
  - "projectd-check: 11/11 checks passed"
  - "Python unittest: 3 passed"
  - "security review: passed after remediation"
  - "code review: passed after remediation"
---

# 採用 Governance Evals v2 Phase 1

## Context

[verified] 既有治理已具備分層規則、最小權限、授權、驗證、歷程留痕與
Skill 供應鏈治理，但原本的 governance eval 主要檢查文字與結構是否存在，
無法證明代理在遭遇不可信內容、高風險工具、記憶污染或中斷續跑時真的遵守規則。

[user-confirmed] 2026-08-21 完成外部研究與本地 gap analysis 後，使用者核准
Phase 1 並在實作、驗證完成後明確選擇「保留」。

## Symptom or goal

把治理從文件規則推進為可測、可追溯且 provider-neutral 的控制基線，同時維持：

- 不依賴付費模型 API、外部服務或秘密資料即可在本機與 CI 執行。
- 評分以結構、事件軌跡與最終狀態為主，不以代理自述「完成」為證據。
- 可執行資產具備單一、可驗證的 repository inventory。
- host runtime、credential 與即時 egress 等 repository 無法證明的狀態，必須明列為
  coverage exclusion，不得假裝已受完整治理。

## Decision

正式採用 Governance Evals v2 Phase 1，保留三層互補控制：

1. 既有 structural governance eval，驗證規則、入口與治理結構。
2. 新增 behavior case catalog 與 deterministic offline grader，以已遮罩的 trial
   trace／final state 驗證授權、source-to-sink、記憶、長任務與完成證據。
3. 新增 unified governance asset inventory 與 validator，登錄 repository 內可驗證的
   agent、skill、tool、MCP、model profile、script 與治理設定，並檢查 schema、路徑、
   capability、風險、owner、版本與 SHA-256 integrity。

三者全部接入 `projectd-check` 與 CI。Phase 1 的 behavior catalog 只驗證 case 與
grader contract；真實模型多次 trial、host adapter、動態 credential／egress inventory、
事故演練與 dashboard 留待後續 phase。

## Alternatives

### rejected：只增加更多文字規則

文字存在不代表執行時會遵守，也不能對回歸、prompt injection、memory poisoning 或
最終副作用做 deterministic 判定，因此不足以填補主要缺口。

### deferred：立即在 CI 呼叫真實模型或付費 API

這會引入 provider lock-in、秘密管理、成本、網路依賴與非決定性。Phase 1 先固定
provider-neutral case／trace／result contract，未來可在不改 grader 語意的前提下接入
不同 host runner。

### deferred：先建立大型 agent framework、dashboard 或集中式控制平面

目前沒有證據顯示這些複雜度比 deterministic contracts 更能提升 task outcome；應先用
簡單基線量到實際缺口，再以回歸或事故證據驅動擴張。

## Resolution

[verified] Phase 1 已完成：

- `evals/governance-behavior-cases.json`：12 個治理行為案例。
- `scripts/governance-behavior-eval.ps1`：catalog 與 redacted trial result 的離線評分器。
- `evals/governance-assets.json`：11 個 repository-verifiable 治理資產。
- `scripts/governance-asset-inventory.ps1`：schema、路徑、風險、能力與 integrity 驗證。
- 三份 JSON Schema、PowerShell contract tests、Python tests 與 CI／`projectd-check` wiring。
- `docs/specs/governance-evals-v2.md`：核准規格與 Phase 1 完成狀態。
- `docs/research/ai-governance-gap-analysis-2026-08-21.md`：外部研究、差距與優先級證據。

安全審查發現的四項問題已修正：PG／QA Bash capability 分級、SHA-256 精確驗證、
reparse point 拒絕，以及已知 secret value 偵測。Code review 發現的 junction cleanup
風險也已修正並通過 focused re-review。

## Verification

- 六個 PowerShell contract suites 全數通過：structural eval、behavior eval、asset
  inventory、hook、fleet inspector、`projectd-check`。
- `projectd-check`：11/11 checks passed。
- Python `unittest`：3 passed。
- `git diff --check`：通過。
- 完整 `pytest` suite 未執行，因本機未安裝 pytest；未為此任務擴張安裝範圍。
- Security review 與 mandatory code-review gate：修正後通過。

## Known limitations

- Catalog validation 不等於真實模型行為成功率；尚未有多次 trial 與統計變異。
- Host runtime 的實際 model version、credential、MCP process、network egress 與 sandbox
  狀態仍屬明示 exclusion。
- Secret marker／known-value 檢查是治理防線，不是完整的企業 secret scanner。
- 模型 alias 仍由 host 提供，尚未建立 model／rule／tool schema upgrade canary gate。

## Applicability

此決策適用於 projectD-core repository 的 Phase 1 治理基線與其 CI。它不代表已具備
完整執行期 containment、事故 kill／revoke／rollback 演練、真實模型可靠度量測或企業級
資產管理；這些能力必須以後續 phase、host adapter 與可重播執行證據另行驗證。
