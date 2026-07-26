from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

RECORDS_SPEC = importlib.util.spec_from_file_location(
    "project_history_records",
    SCRIPTS / "project_history_records.py",
)
assert RECORDS_SPEC and RECORDS_SPEC.loader
records = importlib.util.module_from_spec(RECORDS_SPEC)
sys.modules[RECORDS_SPEC.name] = records
RECORDS_SPEC.loader.exec_module(records)

RUNTIME_SPEC = importlib.util.spec_from_file_location(
    "project_history_runtime",
    SCRIPTS / "project_history_runtime.py",
)
assert RUNTIME_SPEC and RUNTIME_SPEC.loader
runtime_module = importlib.util.module_from_spec(RUNTIME_SPEC)
sys.modules[RUNTIME_SPEC.name] = runtime_module
RUNTIME_SPEC.loader.exec_module(runtime_module)


def write_record(repo: Path, title: str = "Reliable local history") -> None:
    history = repo / "docs" / "history"
    history.mkdir(parents=True, exist_ok=True)
    record = records.HistoryRecord(
        project=repo.name,
        date="2026-07-27",
        title=title,
        kind="decision",
        status="accepted",
        evidence_level="verified",
        body="## Context\nKeep history local.\n\n## Resolution\nUse an explicit runtime.",
        commits=("abc1234",),
        verified_by=("pytest",),
    )
    (history / record.filename).write_text(record.to_markdown(), encoding="utf-8")


def make_runtime(tmp_path: Path, **kwargs: object) -> object:
    core = tmp_path / "projectD-core"
    core.mkdir()
    return runtime_module.LocalHistoryRuntime(
        core_root=core,
        runtime_root=core / ".local" / "project-history",
        **kwargs,
    )


def test_migrates_existing_allowlist_and_reports_active_mode(tmp_path: Path) -> None:
    repo = tmp_path / "sample"
    repo.mkdir()
    core = tmp_path / "projectD-core"
    local = core / ".local" / "project-history"
    local.mkdir(parents=True)
    (local / "projects.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "projects": [
                    {
                        "name": "sample",
                        "path": str(repo),
                        "include_auxiliary": False,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    runtime = runtime_module.LocalHistoryRuntime(
        core_root=core,
        runtime_root=local,
    )
    status = runtime.status()

    assert status["mode"] == "hybrid"
    assert status["allowlist_count"] == 1
    assert (local / "runtime.json").exists()
    assert runtime.list_projects()[0].name == "sample"


def test_project_commands_manage_explicit_allowlist(tmp_path: Path) -> None:
    runtime = make_runtime(tmp_path)
    repo = tmp_path / "sample"
    repo.mkdir()

    added = runtime.add_project(repo, include_auxiliary=True)

    assert added.name == "sample"
    assert runtime.list_projects() == [added]
    removed = runtime.remove_project("sample")
    assert removed == added
    assert runtime.list_projects() == []


def test_lexical_rebuild_and_query_report_mode(tmp_path: Path) -> None:
    runtime = make_runtime(tmp_path)
    repo = tmp_path / "sample"
    write_record(repo)
    runtime.set_mode("lexical")
    runtime.add_project(repo)

    rebuilt = runtime.rebuild()
    response = runtime.query("local history")

    assert rebuilt["mode"] == "lexical"
    assert response.mode == "lexical"
    assert response.results[0]["project"] == "sample"


def test_rebuild_keeps_old_index_when_new_project_is_invalid(tmp_path: Path) -> None:
    runtime = make_runtime(tmp_path)
    good = tmp_path / "good"
    write_record(good, "Known good history")
    runtime.set_mode("lexical")
    runtime.add_project(good)
    runtime.rebuild()
    database = runtime.paths.database
    original = database.read_bytes()

    bad = tmp_path / "bad"
    history = bad / "docs" / "history"
    history.mkdir(parents=True)
    (history / "invalid.md").write_text(
        """---
project: bad
date: 2026-07-27
type: decision
status: accepted
evidence_level: inferred
---
# Invalid

This must fail formal Record validation.
""",
        encoding="utf-8",
    )
    runtime.add_project(bad)

    with pytest.raises(ValueError, match="evidence level"):
        runtime.rebuild()

    assert database.read_bytes() == original
    assert runtime.query("known good").results[0]["project"] == "good"
    assert list(database.parent.glob("*.next-*.db")) == []


def test_hybrid_never_silently_falls_back_to_lexical(tmp_path: Path) -> None:
    def unavailable_embedding(_: object) -> object:
        raise RuntimeError("approved model is unavailable")

    runtime = make_runtime(tmp_path, embedding_factory=unavailable_embedding)
    repo = tmp_path / "sample"
    write_record(repo)
    runtime.add_project(repo)

    with pytest.raises(RuntimeError, match="approved model is unavailable"):
        runtime.rebuild()

    assert not runtime.paths.database.exists()


def test_runtime_uses_git_process_adapter_for_auxiliary_evidence(
    tmp_path: Path,
) -> None:
    class FakeGitReader:
        def __init__(self) -> None:
            self.calls: list[tuple[str, ...]] = []

        def run(self, _: Path, arguments: object) -> str:
            values = tuple(arguments)
            self.calls.append(values)
            if values == ("ls-files",):
                return "README.md\n"
            return ""

    git_reader = FakeGitReader()
    runtime = make_runtime(tmp_path, git_reader=git_reader)
    repo = tmp_path / "sample"
    write_record(repo)
    (repo / "README.md").write_text("# Sample\nAuxiliary evidence.", encoding="utf-8")
    runtime.set_mode("lexical")
    runtime.add_project(repo, include_auxiliary=True)

    runtime.rebuild()

    assert ("ls-files",) in git_reader.calls
    assert any(call[0] == "log" for call in git_reader.calls)


def test_candidate_scan_and_exclude_remain_local(tmp_path: Path) -> None:
    class CandidateGitReader:
        def run(self, _: Path, arguments: object) -> str:
            values = tuple(arguments)
            if values[0] == "log":
                return (
                    "abc1234\x1f2026-07-27\x1f"
                    "feat: reliable local history\x1e"
                )
            return ""

    runtime = make_runtime(tmp_path, git_reader=CandidateGitReader())
    repo = tmp_path / "sample"
    repo.mkdir()
    runtime.add_project(repo)

    scanned = runtime.scan_candidates("sample", limit=5)
    candidate_id = scanned[0].candidate_id
    disposition = runtime.exclude_candidate(candidate_id)

    assert runtime.list_candidates() == []
    serialized = disposition.read_text(encoding="utf-8")
    assert "reliable local history" not in serialized
    assert not list(repo.glob("docs/history/*.md"))


def test_runtime_retain_verifies_index_before_promoting_record(
    tmp_path: Path,
) -> None:
    class CandidateGitReader:
        def run(self, _: Path, arguments: object) -> str:
            values = tuple(arguments)
            if values[0] == "log":
                return (
                    "abc1234\x1f2026-07-27\x1f"
                    "feat: reliable local history\x1e"
                )
            return ""

    runtime = make_runtime(tmp_path, git_reader=CandidateGitReader())
    repo = tmp_path / "sample"
    repo.mkdir()
    runtime.set_mode("lexical")
    runtime.add_project(repo)
    candidate = runtime.scan_candidates("sample", limit=5)[0]
    draft = tmp_path / "draft.md"
    draft.write_text(
        records.HistoryRecord(
            project="sample",
            date="2026-07-27",
            title="Reliable local history",
            kind="decision",
            status="accepted",
            evidence_level="verified",
            body="## Resolution\nUse a local runtime.",
            commits=("abc1234",),
            verified_by=("pytest",),
        ).to_markdown(),
        encoding="utf-8",
    )

    record_path = runtime.retain_candidate(candidate.candidate_id, draft)

    assert record_path.exists()
    assert records.HistoryRecord.from_path(record_path).status == "accepted"
    assert runtime.list_candidates() == []
    assert runtime.scan_candidates("sample", limit=5) == []
    assert list(runtime.paths.root.glob("record.verify-*.db")) == []
