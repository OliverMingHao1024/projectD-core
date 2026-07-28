---
status: accepted
---

# Detect FeaturePage drift without automatic mutation

FeaturePage 固定 verified commit、bounded source paths 與 digest。`knowledge-lint` 以手動或 CI 執行，持久報告 default branch 的來源漂移；`knowledge-query` 在回答前比較目前 workspace 的 HEAD 與 working tree，若不一致則標示 RuntimeStale、停止把頁面當成現行事實並回讀最新 code/test。任何 drift 偵測都不得自動修改 Wiki；只有 KnowledgePromotion PR 能更新頁面與 `last_verified`。
