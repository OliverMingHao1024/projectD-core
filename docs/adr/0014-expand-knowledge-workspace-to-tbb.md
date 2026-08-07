---
status: accepted
---

# Expand KnowledgeWorkspace scope to TBB with a TA23001 tracer bullet

`tbb` 成為 KnowledgeWorkspace 的受管 source system，沿用 ADR 0013 的
system-agnostic schema、validator、registry 與 lifecycle。第一個垂直切片只納入
`TBB_Web` 與 `TBB_Trade`，以 TA23001「亞資融資保全服務」作為跨 repository
FeaturePage；`TBB_MI` 與 `TBB_PlatformDll` 等來源等實際功能需要時再以獨立 manifest
擴充。TA23001 頁面與 pinned manifests 先存在於 candidate branch，只有 repository
owner 回讀 material claims、確認來源並經 pull request promotion 後才能標為
`verified` 並進入正式 index；promotion 前 query 必須 abstain，不得將 candidate 當成
現行事實。TBB 原始 repository 的程式碼、測試與正式需求仍是最終權威。
