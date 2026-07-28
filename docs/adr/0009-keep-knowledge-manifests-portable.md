---
status: accepted
---

# Keep knowledge manifests portable and local paths private

Committed KnowledgeWorkspace manifests 只保存穩定 repository ID、remote URL、commit、相對路徑與 digest，不保存絕對本機路徑。每台裝置以 Git ignored KnowledgeWorkspaceRegistry 將 ID 對應至 canonical local root；query、lint 與 ingest 只能存取 allowlist 內的 root，遇到 path traversal 或 symlink／junction 越界時 fail closed。
