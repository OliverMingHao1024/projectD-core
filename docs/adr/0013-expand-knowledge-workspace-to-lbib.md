---
status: accepted
---

# Expand KnowledgeWorkspace scope to lbib alongside intentype

System Feature Wiki 的 Phase 0 基礎設施（schema、validator、KnowledgeWorkspaceRegistry）改為系統無關（system-agnostic）建置，不再假設單一來源系統。`lbib` 與 `intentype` 並列為 KnowledgeWorkspace 第二個受管來源系統；`repository_id` 與 `system` 分離，讓一個 system（如 `lbib`）可對應多個 git repository（`lbib_Web`、`lbib_Trade_New`、`lbib_PlatformDll_New`），FeaturePage 透過 `source_manifests` 陣列同時引用跨 repository 的來源。這項決策讓兩個系統可共用同一份驗證工具與生命週期規則，不必等其中一個系統先跑完整個 PoC 驗收才能開始第二個系統的 Phase 0 建置；但 lbib 的 Initial FeaturePages 選擇、candidate 撰寫與 promotion 仍是獨立於本決策的後續步驟，不隨本 ADR 自動產生。
