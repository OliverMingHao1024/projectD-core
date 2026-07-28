---
status: accepted
---

# Treat review as an event, not a FeaturePage status

FeaturePage 不使用 `reviewed` lifecycle status。審查只記錄於 promotion PR 或 review metadata；candidate 經審查後只能成為 `verified`、`needs-evidence` 或 `rejected`。正式 query 與 deterministic index 只使用 `verified`；`needs-evidence` 留在 PR，`stale` 與 `superseded` 只供明確 audit/history 使用，避免把「有人讀過」或「曾經正確」誤解為現行事實。
