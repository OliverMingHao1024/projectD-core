# After-Action 紀錄

事件驅動的踩坑/回顧紀錄。每次踩到值得記住的坑，新增一個檔案：
`YYYY-MM-DD-簡短標題.md`，內容至少包含：發生什麼、為什麼、下次怎麼避免。

目前為空，尚無紀錄。

Governance Evals v2 Phase 2 對真實事件採以下 intake contract：

1. 先依上述格式建立並人工接受 after-action 紀錄；不得把安全審查 finding、假想情境或
   synthetic drill 寫成已發生事件。
2. 建立 `source: incident-derived` 的 privacy-preserving task trace，只保留 metadata、
   observable control events 與 final state，並以 `source_ref` 指向本目錄內的紀錄。
3. 在 `evals/governance-security-traces.json` 的 `after_action_regressions` 建立
   `evidence_level: verified` mapping，連到既有 behavior case 或另經核准的新 case。
4. 執行 `scripts/governance-trace-eval.ps1`；trace、case、control evidence 或 source
   linkage 任一不一致都必須 fail closed。

目前 canonical suite 只有明示為 `simulated` 的演練 mapping，並保留
`no-verified-incidents` coverage exclusion；這不代表已發生真實事故。
