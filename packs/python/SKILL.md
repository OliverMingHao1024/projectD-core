---
name: python
description: Python stack conventions for PG — scripts/automation, web backend (FastAPI/Flask/Django), and data/analysis.
---

# Python Pack

涵蓋三種常見情境：腳本/自動化工具、Web 後端、資料/分析。套件管理器/測試框架
依專案而定（pip、poetry、uv 都可能遇到）——先確認該專案實際用哪個，不要假設。

## 專案結構慣例

- **腳本/自動化工具**：單一腳本可以就是一個檔案；一旦超過一個檔案的規模，
  拆成 `main.py` + 功能模組，不要把所有邏輯塞進一個檔案。
- **Web 後端（FastAPI/Flask/Django）**：依框架慣例分層（routers/views、
  services、models）；不要把商業邏輯直接寫在路由函式裡。
- **資料/分析**：探索階段可以用 notebook，但要進版本控制/重複執行的部分
  要轉成 `.py` 腳本或函式，不要讓最終產物只存在 notebook cell 執行順序裡。

## 型別註記 / Lint 慣例

- 公開函式（尤其是模組邊界、API 端點）要有型別註記；純內部小函式可以視情況省略。
- 待確認：實際專案用 mypy 還是 ruff（或都用）——先看該專案有沒有既有設定檔
  （`mypy.ini`、`pyproject.toml` 的 `[tool.ruff]`），跟隨既有選擇，不強行換工具。

## Code Review Checklist

- [ ] 例外處理是否吞掉了原始錯誤訊息（`except: pass` 或裸 `except Exception`）？
- [ ] Web 後端：輸入是否有驗證（Pydantic model / 框架內建驗證），不信任外部輸入？
- [ ] 資料處理：是否對照過資料量級選擇合適的方式（例如大檔案不要整個讀進記憶體）？
- [ ] 是否有寫死的路徑/密鑰，應該用環境變數或設定檔？
- [ ] 迴圈/遞迴是否有明確的終止條件？

## 測試慣例

- 測試框架：pytest（除非該專案已有其他既有選擇）。
- 測試檔案：`test_*.py`，鏡射被測模組的結構。
- Web 後端測試：用框架提供的 test client（FastAPI `TestClient`、Django
  `TestCase` 等），不直接發真實網路請求。
- 新增行為或修復 bug 時，先寫能描述期望或重現問題的失敗測試（Red），
  再做最小實作（Green），最後在測試保護下重構（Refactor）。
- Red 必須因目標行為尚未成立而失敗，不接受 import、fixture 或環境錯誤造成的假紅。
- 單次腳本或既有專案沒有測試基礎設施時，先保留可重現輸入／輸出作為回歸證據；
  不擅自新增套件，確有長期價值時再提案導入 pytest。

## Build / Lint 指令

```bash
# 依專案實際套件管理器擇一，先確認該專案用哪個
pip install -r requirements.txt   # 或
poetry install                    # 或
uv sync

pytest
```

<!-- 待補：實際專案出現後，補上該專案選定的 lint/format 工具鏈具體指令
     （ruff/black/mypy 的實際 config 與指令），不預先假設所有專案都用同一套。 -->
