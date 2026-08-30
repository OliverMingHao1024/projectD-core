---
status: accepted
---

# Separate the KnowledgeWorkspace from projectD-core

SystemFeatureWiki 內容位於獨立 private `projectD-knowledge` repository。KnowledgeWorkspace 擁有具體 page/manifest schema、validator、fixtures 與 CI；projectD-core 只管理 workspace registry、支援的 schema version、生命周期與安全底線，以及 fail-closed 的唯讀 query adapter。來源 repository 仍是程式碼、測試與正式文件的最終權威，schema 與 Wiki 內容不得在兩個 repository 間維護副本。


## Current authority

- Core-side registration, supported-version, query-adapter, lifecycle, and security contract:
  [KnowledgeWorkspace core boundary](../specs/knowledge-workspace-boundary.md)
- Workspace-owned specification and ADRs:
  [projectD-knowledge](https://github.com/OliverMingHao1024/projectD-knowledge/tree/main)
