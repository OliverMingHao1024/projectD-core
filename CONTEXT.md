# projectD-core

定義共用 AI 治理與可驗證專案歷程的核心語言。

## Language

**CanonicalSkill**:
由 projectD-core 維護、通過治理審查，並供一個或多個 AI Agent 共用的正式 Skill；其落點依適用範圍分為 `core/skills/` 或 `packs/`。
_Avoid_: InstalledSkill, ExternalSkill, AgentCopy

**SkillCandidate**:
從單一外部來源路徑識別、尚未成為 CanonicalSkill 的待審 Skill；具有獨立 ID、來源版本、生命週期狀態與審查紀錄。
_Avoid_: RepositoryCandidate, InstalledSkill, StagedPack

**SkillSource**:
提供一個或多個 SkillCandidate 的外部 repository；集中記錄來源位置、授權與最近觀察版本，但不代表其中所有 Skills 都被信任或採用。
_Avoid_: SkillPack, CanonicalSkill, TrustedRepository

**SkillRegistry**:
保存 SkillSource、SkillCandidate 與 CanonicalSkill 之間機器可讀關係及生命週期狀態的唯一資料來源；不保存人工決策理由。
_Avoid_: CandidateLog, SkillDocumentation, SourceOfRationale

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

**SystemFeatureWiki**:
以可回讀來源描述系統能力、行為與限制的受治理知識層；協助功能定位、影響分析及角色訓練，但不是變更權威或最終事實來源。
_Avoid_: CodeWiki, SourceOfTruth, FeatureDocumentation

**FeaturePage**:
SystemFeatureWiki 中以單一使用者可觀察能力為邊界的知識單位；描述行為、限制與修改影響，程式模組及檔案只作為可回讀的定位資訊。
_Avoid_: ModulePage, FileSummary, CodeDocumentation

**KnowledgeWorkspace**:
獨立版本控制、保存來源 manifest、候選內容與經審核 FeaturePage 的知識工作區；可由 projectD 查詢，但不取代來源 repository 的程式碼、測試與正式文件。
_Avoid_: WikiCopy, SourceRepository, projectDCoreContent

**KnowledgePromotion**:
將通過 deterministic validation 且經授權 reviewer 核准的 candidate diff，透過 PR 合併為正式 FeaturePage 的治理動作；生成、lint 或 LLM critique 本身都不構成升格。
_Avoid_: AutoPublish, LLMApproval, Ingest

**RuntimeStale**:
查詢當下發現目前 source HEAD 或 working tree 與 FeaturePage 的 verified manifest 不一致的暫時狀態；不自動修改 Wiki，但禁止把該頁當成現行事實。
_Avoid_: Verified, PersistedStale, AutoUpdate

**KnowledgeWorkspaceRegistry**:
每台裝置本機保存且不進 Git 的 allowlist，將穩定 workspace／repository ID 對應至 canonical local root；不保存 Wiki 內容、來源內容或憑證。
_Avoid_: GlobalPath, SharedIndex, RemoteRegistry

**KnowledgeEvidenceSource**:
可由 source manifest 固定版本、相對路徑與 digest，並作為 FeaturePage 主張依據的受控文件來源；其內容未經 KnowledgePromotion 不屬於 verified knowledge。
_Avoid_: KnowledgeWorkspace, VerifiedWiki, SourceOfTruth

**KnowledgeProjection**:
由 verified FeaturePage deterministic 產生、具有明確 ownership marker 的唯讀呈現；可供 Obsidian 等工具閱讀，但不是知識來源，人工修改不得回寫或構成 KnowledgePromotion。
_Avoid_: SyncedWiki, ObsidianSource, KnowledgeCopy
