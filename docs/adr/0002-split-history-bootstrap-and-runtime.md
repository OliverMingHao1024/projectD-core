---
status: accepted
---

# Split history bootstrap from local runtime

PowerShell Bootstrap 只負責 Python、venv、套件、模型與下載同意；Python
`LocalHistoryRuntime` 擁有 allowlist、mode、index、query 與狀態規則，
PowerShell command 只是 Windows adapter。Runtime 預設 hybrid、允許明確
選擇 lexical、禁止靜默降級，並以 transactional rebuild 保護既有 index。

