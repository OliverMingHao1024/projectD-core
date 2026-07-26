# projectD-core

定義共用 AI 治理與可驗證專案歷程的核心語言。

## Language

**HistoryCandidate**:
尚未經人工確認、不能視為事實或建議的歷程候選。
_Avoid_: DraftRecord, UnconfirmedRecord

**HistoryRecord**:
經人工確認並保存，且明確標示狀態與證據等級的正式歷程。
_Avoid_: Candidate, ConversationLog

**HistoryProjection**:
由 Candidate 或 Record 衍生的唯讀呈現，不是歷程事實來源。
_Avoid_: SourceRecord

**CandidateDisposition**:
本機保存的 Candidate 審查結果，用來避免已排除候選被重複提出；不包含候選內容。
_Avoid_: RejectedRecord, HistoryRecord

**GovernanceWiring**:
projectD-core 與 AI 工具或受治理專案之間，由 projectD-core 擁有且可檢查、更新與移除的治理連結。
_Avoid_: Installation, ManualSetup

**LocalHistoryRuntime**:
在單一裝置上，依明確核准的專案範圍建立並查詢衍生歷程索引的執行環境。
_Avoid_: SharedHistoryStore, CloudHistory
