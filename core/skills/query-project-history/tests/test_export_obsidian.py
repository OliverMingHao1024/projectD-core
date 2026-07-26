from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "export_obsidian.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("export_obsidian", SCRIPT)
assert SPEC and SPEC.loader
export_obsidian = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export_obsidian)


def test_export_marks_candidates_unconfirmed(tmp_path: Path) -> None:
    candidates = tmp_path / "candidates.json"
    lexical = tmp_path / "lexical.json"
    hybrid = tmp_path / "hybrid.json"
    output = tmp_path / "vault"
    candidates.write_text(
        json.dumps(
            {
                "projects": {
                    "sample": [
                        {
                            "project": "sample",
                            "date": "2026-07-27",
                            "title": "Candidate",
                            "type": "bug",
                            "status": "experimental",
                            "evidence_level": "inferred",
                            "evidence": ["commit:abc123"],
                            "review": ["Confirm root cause?"],
                        }
                    ]
                }
            }
        ),
        encoding="utf-8",
    )
    result = {
        "hits": 1,
        "total": 1,
        "hit_rate": 1.0,
        "cases": [{"query": "Question", "rank": 1}],
    }
    lexical.write_text(json.dumps(result), encoding="utf-8")
    hybrid.write_text(json.dumps(result), encoding="utf-8")

    paths = export_obsidian.export(
        candidates,
        lexical,
        hybrid,
        output,
        {"sample": tmp_path / "sample"},
        {"sample": "https://github.com/example/sample"},
    )

    project_page = (output / "sample-history.md").read_text(encoding="utf-8")
    assert len(paths) == 3
    assert "未確認的歷程候選" in project_page
    assert "`experimental`" in project_page
    assert "確認方式（請勾選一項）" in project_page
    assert "- [ ] 確認並保留：" in project_page
    assert "- [ ] 不確定，暫時保留：" in project_page
    assert "- [ ] 排除：" in project_page
    assert "不需要回想技術細節" in project_page
    assert "Confirm root cause?" not in project_page
    assert "推論（`inferred`）" in project_page
    assert "https://github.com/example/sample/commit/abc123" in project_page


def test_export_normalizes_candidate_status_to_experimental(tmp_path: Path) -> None:
    candidates = tmp_path / "candidates.json"
    lexical = tmp_path / "lexical.json"
    hybrid = tmp_path / "hybrid.json"
    output = tmp_path / "obsidian"
    project = tmp_path / "sample"
    project.mkdir()
    candidates.write_text(
        json.dumps(
            {
                "projects": {
                    "sample": [
                        {
                            "project": "sample",
                            "date": "2026-07-27",
                            "title": "Unreviewed",
                            "type": "decision",
                            "status": "accepted",
                            "evidence_level": "inferred",
                            "evidence": ["commit:abc1234"],
                        }
                    ]
                }
            }
        ),
        encoding="utf-8",
    )
    result = {"hits": 0, "total": 0, "hit_rate": 0.0, "cases": []}
    lexical.write_text(json.dumps(result), encoding="utf-8")
    hybrid.write_text(json.dumps(result), encoding="utf-8")

    export_obsidian.export(
        candidates,
        lexical,
        hybrid,
        output,
        {"sample": project},
    )

    page = (output / "sample-history.md").read_text(encoding="utf-8")
    assert "待確認（`experimental`）" in page
    assert "已採用（`accepted`）" not in page
