---
status: accepted
date: 2026-07-27
domain: governance-wiring
---

# Manage governance wiring as desired state

`GovernanceWiring` 以單一 desired state 描述 managed entry blocks、skill
junction、agent／command ownership 與 environment 設定；setup、check 與
remove 共用 inspect、plan、apply lifecycle。套用前必須完成 ownership
preflight，失敗時只回滾本次修改且已確認 owned 的項目，絕不改動非 owned 資源。
