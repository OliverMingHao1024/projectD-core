from __future__ import annotations

import importlib.util
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

SCRIPT = (
    Path(__file__).parents[1] / "scripts" / "project_history_records.py"
)
SPEC = importlib.util.spec_from_file_location("project_history_records", SCRIPT)
assert SPEC and SPEC.loader
records = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = records
SPEC.loader.exec_module(records)


def candidate() -> object:
    return records.HistoryCandidate(
        project="sample",
        date="2026-07-27",
        title="Make local history reliable",
        kind="decision",
        evidence_level="inferred",
        rationale="unknown",
        commits=("abc1234",),
        evidence=("commit:abc1234",),
    )


def record() -> object:
    return records.HistoryRecord(
        project="sample",
        date="2026-07-27",
        title="Make local history reliable",
        kind="decision",
        status="accepted",
        evidence_level="verified",
        body=(
            "## Context\nLocal history must remain device-local.\n\n"
            "## Resolution\nUse an explicit local runtime."
        ),
        commits=("abc1234",),
        verified_by=("pytest",),
    )


def workflow(tmp_path: Path) -> object:
    return records.RecordLifecycle(
        local_root=tmp_path / ".local" / "project-history",
        records_root=tmp_path / "repo" / "docs" / "history",
    )


def test_retain_verifies_record_before_removing_candidate(tmp_path: Path) -> None:
    lifecycle = workflow(tmp_path)
    item = candidate()
    candidate_path = lifecycle.queue(item)
    verified: list[Path] = []

    def verify(path: Path) -> None:
        loaded = records.HistoryRecord.from_path(path)
        assert loaded.status == "accepted"
        verified.append(path)

    record_path = lifecycle.retain(item.candidate_id, record(), verify=verify)

    assert verified == [record_path]
    assert record_path.exists()
    assert not candidate_path.exists()
    assert lifecycle.load_candidate(item.candidate_id) is None


def test_retain_rolls_back_record_when_verification_fails(tmp_path: Path) -> None:
    lifecycle = workflow(tmp_path)
    item = candidate()
    candidate_path = lifecycle.queue(item)

    def fail_verification(_: Path) -> None:
        raise RuntimeError("index verification failed")

    try:
        lifecycle.retain(item.candidate_id, record(), verify=fail_verification)
    except RuntimeError as error:
        assert "index verification failed" in str(error)
    else:
        raise AssertionError("retain must fail when verification fails")

    assert candidate_path.exists()
    assert list((tmp_path / "repo" / "docs" / "history").glob("*.md")) == []


def test_defer_keeps_candidate_local_without_record(tmp_path: Path) -> None:
    lifecycle = workflow(tmp_path)
    item = candidate()
    candidate_path = lifecycle.queue(item)

    deferred = lifecycle.defer(item.candidate_id)

    assert deferred == item
    assert candidate_path.exists()
    assert not (tmp_path / "repo" / "docs" / "history").exists()


def test_exclude_removes_content_and_keeps_metadata_only(tmp_path: Path) -> None:
    lifecycle = workflow(tmp_path)
    item = candidate()
    candidate_path = lifecycle.queue(item)
    reviewed_at = datetime(2026, 7, 27, 4, 0, tzinfo=UTC)

    disposition_path = lifecycle.exclude(
        item.candidate_id,
        reviewed_at=reviewed_at,
    )

    assert not candidate_path.exists()
    disposition = json.loads(disposition_path.read_text(encoding="utf-8"))
    assert disposition == {
        "candidate_id": item.candidate_id,
        "disposition": "excluded",
        "reviewed_at": "2026-07-27T04:00:00+00:00",
    }
    serialized = disposition_path.read_text(encoding="utf-8")
    assert item.title not in serialized
    assert "content" not in serialized


def test_excluded_candidate_is_not_queued_again(tmp_path: Path) -> None:
    lifecycle = workflow(tmp_path)
    item = candidate()
    lifecycle.queue(item)
    lifecycle.exclude(item.candidate_id)

    try:
        lifecycle.queue(item)
    except records.CandidateExcluded as error:
        assert item.candidate_id in str(error)
    else:
        raise AssertionError("excluded candidate must not re-enter the local queue")
