---
status: accepted
---

# Use Git pull requests as the KnowledgePromotion audit

KnowledgeWorkspace 的 candidate 只存在於 feature branch 與 pull-request diff，`main` 不保存 rejected candidate、獨立 review 文件或 append-only operation log。Validator 與 CI 結果留在 PR checks；核准後合併為 verified FeaturePage，證據不足或拒絕則關閉 PR 並保留理由。正式 index 只能由 `main` 上的頁面 deterministic 產生或驗證。
