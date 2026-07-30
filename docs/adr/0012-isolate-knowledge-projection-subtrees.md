# Isolate knowledge projections to managed subtrees

KnowledgeProjection exporter 只擁有明確登錄的 generated subtree，不要求整個 Obsidian Vault clean。Exporter 僅能建立或更新帶正確 ownership marker 的檔案；若受管子樹包含人工修改、未知檔案或 ownership 漂移則 fail closed。這項決策允許人工文件與其他未提交工作並存，同時避免 exporter 覆寫或提交不相關內容。
