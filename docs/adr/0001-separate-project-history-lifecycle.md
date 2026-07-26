---
status: accepted
---

# Separate the project history lifecycle

`HistoryCandidate`、`HistoryRecord` 與 `HistoryProjection` 是不同概念：
Candidate 只留本機，人工確認保留後才產生可進 Git 的 Record，Projection
永遠可重建且不是事實來源。被排除的 Candidate 只留下不含內容的本機
`CandidateDisposition`，避免未確認內容進入共享歷程，也避免同一候選反覆出現。
