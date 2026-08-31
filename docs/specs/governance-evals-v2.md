# Governance Evals v2

- 狀態：approved；Phase 1、2 complete；Phase 3 依子規格持續執行
- 核准日期：2026-08-21
- Phase 3：[`governance-evals-v2-phase-3.md`](governance-evals-v2-phase-3.md)
- 完整採用與實作歷程：[projectD-knowledge archive](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/design/governance-evals-v2-full-history.md)

## 權威邊界

本規格定義 repository-local、provider-neutral 的治理評估契約。Phase 1／2 的完成證據只涵蓋
contracts、synthetic fixtures 與 deterministic graders；不得據此宣稱真實模型、host runtime、
credential、MCP、sandbox、approval 或 egress 已通過驗證。

| 階段 | 狀態 | 現行邊界 |
|---|---|---|
| Phase 1 | complete | Behavior catalog、asset inventory、validator、grader、CI wiring。 |
| Phase 2 | complete | Metadata-only security traces、control drills、verified incident intake。 |
| Phase 3 | in progress | Host adapters、durable operation log、hook contracts 與 upgrade gate 已完成；live evidence 尚未完成。 |
| Phase 4 | not started | Skill routing、context budget、stale/conflict detection 與 evidence-driven gardening。 |

## Behavior 與 trace 契約

- Case 必須有唯一 ID、suite、risk tier、purpose、minimum trials、pass threshold、預期 outcome、
  observable final state、required／forbidden events 與 action budget。
- Trial 必須有唯一 trial ID、case ID、agent／model／harness metadata、結構化 events、outcome 與
  final state；不得保存 raw prompt、chain-of-thought、秘密或未遮罩私人資料。
- Grader 只接受 observable state 與 tool events，不接受 agent 的成功宣告取代證據。
- Trace 使用單調 sequence、唯一 event ID 與 previous-event chain；斷鏈、重排、重複事件、
  未授權成功 action 或缺 final state 必須 fail closed。
- Canonical Phase 2 traces 只使用 synthetic fixtures；`host-captured` 必須由 Phase 3 provenance
  contract 驗證後才能被接受。
- Incident-derived trace 只能引用 `vault/after-action/YYYY-MM-DD-*.md` 中已接受且 verified 的證據；
  沒有真實事件時必須保留 coverage exclusion，不得把演練標成事故。

## Asset inventory 契約

每個 asset 必須記錄 identity、kind、owner、status、risk tier、source/version/integrity、capabilities、
approval/isolation/disable/rollback controls 與對應 eval case。

Validator 必須 fail closed：

- active 高風險資產缺 approval 或 disable procedure；
- active executable asset 缺 integrity evidence；
- private data、untrusted content、external communication 同時存在卻缺 source/sink policy；
- credential 含 secret value，或缺 scope、audience、storage、expiry policy；
- repository-local source 越界、不存在或指向 reparse path；
- related eval case 不存在。

Repository-local text executable 的 integrity 以 UTF-8、LF canonical bytes 計算 SHA-256；
CRLF／LF checkout 差異不得造成誤判，其他內容變更仍必須失敗。

## Canonical assets

- Behavior 與 trace catalogs：`evals/catalogs/`
- Schemas：`evals/schemas/`
- Validators／graders：`scripts/governance-*.ps1`
- Unified entry point：`scripts/projectd-check.ps1 -GovernanceEvals`
- CI：`.github/workflows/governance.yml`

## 驗收不變條件

1. Canonical behavior catalog 至少 12 個案例且 validation 通過。
2. 合法 trial 通過；越權、外傳、虛假完成與 trace integrity failures 必須失敗。
3. Canonical inventory 通過；lethal-trifecta、缺 disable control、內嵌秘密與未知 eval 必須失敗。
4. 攻擊 traces 至少涵蓋 prompt injection、memory poisoning、tool misuse、exfiltration。
5. Control drills 至少涵蓋 credential revoke、tool disable、egress deny、rollback。
6. Governance Evals、focused contracts、security review 與 Standards／Spec review 全數通過。

## 現行驗證

```powershell
pwsh -NoProfile -File scripts/projectd-check.ps1 -SkipGlobal -GovernanceEvals
```

真實 host trial、跨模型比較、checkpoint recovery 與 upgrade gate 的額外限制，以 Phase 3 子規格為準。
