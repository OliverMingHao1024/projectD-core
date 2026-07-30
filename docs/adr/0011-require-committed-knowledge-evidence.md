# Require committed knowledge evidence

Source manifest 只能引用 KnowledgeEvidenceSource 中已提交的 Git commit、相對路徑與 content digest；working tree、staged changes 與未提交文件不得作為 verified FeaturePage 的證據。這項決策犧牲即時收錄的便利性，換取可重現、可回讀且不受本機暫態修改影響的知識來源。
