from __future__ import annotations

import importlib.util
import json
import sqlite3
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "history_search.py"
SPEC = importlib.util.spec_from_file_location("history_search", SCRIPT)
assert SPEC and SPEC.loader
history_search = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(history_search)


class FakeEmbedding:
    name = "fake-multilingual"

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._embed(text) for text in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._embed(text)

    @staticmethod
    def _embed(text: str) -> list[float]:
        groups = (
            ("close", "exit", "關閉", "退出"),
            ("setting", "control panel", "設定", "控制面板"),
            ("failure", "failed", "失敗", "錯誤"),
        )
        lowered = text.lower()
        return [float(any(word in lowered for word in group)) for group in groups]


def test_prepare_model_reports_backend_and_dimension() -> None:
    result = history_search.prepare_model(FakeEmbedding())

    assert result == {"model": "fake-multilingual", "dimensions": 3}


def test_fastembed_requires_explicit_local_cache(
    monkeypatch: object,
) -> None:
    monkeypatch.delenv("FASTEMBED_CACHE_PATH", raising=False)  # type: ignore[attr-defined]

    try:
        history_search.FastEmbedEmbedding()
    except history_search.EmbeddingUnavailable as error:
        assert "explicit local model cache" in str(error)
    else:
        raise AssertionError("hybrid mode must not use an implicit download cache")


def write_history(repo: Path) -> None:
    history = repo / "docs" / "history"
    history.mkdir(parents=True)
    (history / "2026-07-27-control-panel.md").write_text(
        f"""---
project: {repo.name}
date: 2026-07-27
type: bug
status: accepted
evidence_level: verified
commits: [abc1234]
---
# Return to control panel
Closing settings must return to the control panel.
""",
        encoding="utf-8",
    )
    (history / "2026-07-26-failed-route.md").write_text(
        f"""---
project: {repo.name}
date: 2026-07-26
type: experiment
status: failed
evidence_level: verified
---
# Direct process exit
The direct exit approach failed verification.
""",
        encoding="utf-8",
    )


def test_index_and_lexical_query_preserve_status(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    write_history(repo)
    db = tmp_path / "history.db"

    count = history_search.index_project(db, repo, include_auxiliary=False)
    results = history_search.search(db, "direct exit", mode="lexical", limit=5)

    assert count == 2
    assert results[0]["status"] == "failed"
    assert results[0]["evidence_level"] == "verified"
    assert results[0]["source"].endswith("2026-07-26-failed-route.md")


def test_hybrid_finds_cross_language_paraphrase(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    write_history(repo)
    db = tmp_path / "history.db"
    embedding = FakeEmbedding()

    history_search.index_project(db, repo, include_auxiliary=False, embedding=embedding)
    results = history_search.search(
        db, "設定畫面關閉後去哪裡", mode="hybrid", limit=5, embedding=embedding
    )

    assert results[0]["title"] == "Return to control panel"
    assert results[0]["vector_score"] > 0


def test_hybrid_without_vectors_fails_explicitly(tmp_path: Path) -> None:
    db = tmp_path / "history.db"
    sqlite3.connect(db).close()

    try:
        history_search.search(db, "anything", mode="hybrid", limit=5)
    except history_search.EmbeddingUnavailable as error:
        assert "embedding" in str(error).lower()
    else:
        raise AssertionError("hybrid search must not silently become lexical")


def test_connect_migrates_existing_index_with_evidence_level(tmp_path: Path) -> None:
    db = tmp_path / "old.db"
    connection = sqlite3.connect(db)
    connection.execute(
        """
        CREATE TABLE documents (
            id INTEGER PRIMARY KEY,
            project TEXT NOT NULL,
            kind TEXT NOT NULL,
            status TEXT NOT NULL,
            date TEXT NOT NULL,
            source TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            vector TEXT,
            embedding_model TEXT
        )
        """
    )
    connection.close()

    migrated = history_search.connect(db)
    columns = {row["name"] for row in migrated.execute("PRAGMA table_info(documents)")}
    migrated.close()

    assert "evidence_level" in columns


def test_index_status_does_not_create_missing_database(tmp_path: Path) -> None:
    db = tmp_path / "missing.db"

    status = history_search.index_status(db)

    assert status == {
        "exists": False,
        "path": str(db.resolve()),
        "total": 0,
        "projects": [],
    }
    assert not db.exists()


def test_index_status_reports_project_counts(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    write_history(repo)
    db = tmp_path / "history.db"
    history_search.index_project(db, repo, include_auxiliary=False)

    status = history_search.index_status(db)

    assert status["exists"] is True
    assert status["total"] == 2
    assert status["projects"] == [
        {"project": "sample", "records": 2, "confirmed": 2, "auxiliary": 0}
    ]


def test_candidate_output_is_unconfirmed(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    repo.mkdir()
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "commit",
            "--allow-empty",
            "-m",
            "fix: recover after reload",
        ],
        cwd=repo,
        check=True,
        capture_output=True,
    )

    candidates = history_search.git_candidates(repo, limit=5)

    assert candidates[0]["status"] == "experimental"
    assert candidates[0]["needs_review"] is True
    assert candidates[0]["evidence_level"] == "inferred"
    assert candidates[0]["rationale"] == "unknown"


def test_auxiliary_index_keeps_commits_with_empty_bodies(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    repo.mkdir()
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "commit",
            "--allow-empty",
            "-m",
            "fix: message only",
        ],
        cwd=repo,
        check=True,
        capture_output=True,
    )

    documents = history_search.auxiliary_documents(repo)

    assert any(item["title"] == "fix: message only" for item in documents)


def test_auxiliary_index_reads_unicode_document_paths(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    document = repo / "docs" / "dev-log" / "讀取失敗.md"
    document.parent.mkdir(parents=True)
    document.write_text("# 圖片讀取失敗\n保留診斷資訊。", encoding="utf-8")
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "add", "."], cwd=repo, check=True, capture_output=True)

    documents = history_search.auxiliary_documents(repo)

    assert any(item["title"] == "圖片讀取失敗" for item in documents)


def test_cli_json_result_contains_evidence(tmp_path: Path, capsys: object) -> None:
    repo = tmp_path / "sample"
    write_history(repo)
    db = tmp_path / "history.db"
    history_search.index_project(db, repo, include_auxiliary=False)

    exit_code = history_search.main(
        ["query", "--db", str(db), "--query", "control panel", "--json"]
    )
    output = json.loads(capsys.readouterr().out)  # type: ignore[attr-defined]

    assert exit_code == 0
    assert output[0]["project"] == "sample"
    assert output[0]["source"]


def test_evaluate_reports_top_five_hit(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    write_history(repo)
    db = tmp_path / "history.db"
    benchmark = tmp_path / "benchmark.json"
    benchmark.write_text(
        json.dumps([{"query": "control panel", "expected": "control-panel.md"}]),
        encoding="utf-8",
    )
    history_search.index_project(db, repo, include_auxiliary=False)

    report = history_search.evaluate(db, benchmark, mode="lexical", limit=5)

    assert report["hits"] == 1
    assert report["hit_rate"] == 1.0


def test_search_can_filter_by_project(tmp_path: Path) -> None:
    first = tmp_path / "first"
    second = tmp_path / "second"
    write_history(first)
    write_history(second)
    db = tmp_path / "history.db"
    history_search.index_project(db, first, include_auxiliary=False)
    history_search.index_project(db, second, include_auxiliary=False)

    results = history_search.search(
        db, "control panel", mode="lexical", limit=5, project="second"
    )

    assert results
    assert {result["project"] for result in results} == {"second"}


def test_lexical_search_matches_cjk_phrase_inside_sentence(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    history = repo / "docs" / "history"
    history.mkdir(parents=True)
    (history / "frontend.md").write_text(
        "# 前端模組化\napp.js 依畫面拆分。", encoding="utf-8"
    )
    db = tmp_path / "history.db"
    history_search.index_project(db, repo, include_auxiliary=False)

    results = history_search.search(
        db, "前端大檔案依不同畫面拆分的歷程", mode="lexical", limit=5
    )

    assert results[0]["title"] == "前端模組化"
