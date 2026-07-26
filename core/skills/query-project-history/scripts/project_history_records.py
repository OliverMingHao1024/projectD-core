from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

RECORD_STATUSES = frozenset({"accepted", "rejected", "failed", "superseded"})
CANDIDATE_EVIDENCE_LEVELS = frozenset(
    {"verified", "user-confirmed", "inferred", "unknown"}
)
RECORD_EVIDENCE_LEVELS = frozenset({"verified", "user-confirmed", "unknown"})


class RecordValidationError(ValueError):
    pass


class CandidateExcluded(RuntimeError):
    pass


def _string_tuple(value: object) -> tuple[str, ...]:
    if value is None:
        return ()
    if isinstance(value, str):
        return (value,) if value else ()
    if isinstance(value, (list, tuple)):
        return tuple(str(item) for item in value if str(item))
    raise RecordValidationError(f"Expected a string list, received {type(value).__name__}")


def parse_frontmatter(text: str) -> tuple[dict[str, object], str]:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.startswith("---\n"):
        return {}, normalized
    end = normalized.find("\n---\n", 4)
    if end < 0:
        return {}, normalized

    metadata: dict[str, object] = {}
    list_key: str | None = None
    for line in normalized[4:end].splitlines():
        stripped = line.strip()
        if list_key and stripped.startswith("- "):
            values = metadata[list_key]
            assert isinstance(values, list)
            values.append(stripped[2:].strip().strip("'\""))
            continue
        list_key = None
        if ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        key = key.strip()
        value = raw_value.strip()
        if not value:
            metadata[key] = []
            list_key = key
        elif value.startswith("[") and value.endswith("]"):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError:
                parsed = [
                    item.strip().strip("'\"")
                    for item in value[1:-1].split(",")
                    if item.strip()
                ]
            metadata[key] = parsed
        else:
            metadata[key] = value.strip("'\"")
    return metadata, normalized[end + 5 :]


def markdown_title(body: str, fallback: str) -> str:
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return fallback


def _body_without_title(body: str) -> str:
    lines = body.strip().splitlines()
    for index, line in enumerate(lines):
        if line.startswith("# "):
            return "\n".join(lines[:index] + lines[index + 1 :]).strip()
    return body.strip()


def _frontmatter_list(values: tuple[str, ...]) -> str:
    return json.dumps(list(values), ensure_ascii=False)


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temporary.write_text(content, encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _slug(title: str) -> str:
    value = re.sub(r"[^\w-]+", "-", title.lower(), flags=re.UNICODE).strip("-_")
    return value or "history"


@dataclass(frozen=True, slots=True)
class HistoryCandidate:
    project: str
    date: str
    title: str
    kind: str
    evidence_level: str = "inferred"
    rationale: str = "unknown"
    commits: tuple[str, ...] = field(default_factory=tuple)
    evidence: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        for name in ("project", "date", "title", "kind"):
            if not getattr(self, name).strip():
                raise RecordValidationError(f"HistoryCandidate.{name} is required")
        if self.evidence_level not in CANDIDATE_EVIDENCE_LEVELS:
            raise RecordValidationError(
                f"Unsupported candidate evidence level: {self.evidence_level}"
            )

    @property
    def candidate_id(self) -> str:
        identity = {
            "project": self.project,
            "date": self.date,
            "title": self.title,
            "kind": self.kind,
            "commits": self.commits,
            "evidence": self.evidence,
        }
        serialized = json.dumps(
            identity,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        return hashlib.sha256(serialized.encode("utf-8")).hexdigest()

    def to_mapping(self) -> dict[str, object]:
        return {
            "candidate_id": self.candidate_id,
            "project": self.project,
            "date": self.date,
            "title": self.title,
            "type": self.kind,
            "status": "experimental",
            "evidence_level": self.evidence_level,
            "rationale": self.rationale,
            "commits": list(self.commits),
            "evidence": list(self.evidence),
            "needs_review": True,
        }

    @classmethod
    def from_mapping(cls, value: Mapping[str, object]) -> HistoryCandidate:
        return cls(
            project=str(value.get("project", "")),
            date=str(value.get("date", "")),
            title=str(value.get("title", "")),
            kind=str(value.get("type", value.get("kind", "experiment"))),
            evidence_level=str(value.get("evidence_level", "inferred")),
            rationale=str(value.get("rationale", "unknown")),
            commits=_string_tuple(value.get("commits")),
            evidence=_string_tuple(value.get("evidence")),
        )


@dataclass(frozen=True, slots=True)
class HistoryRecord:
    project: str
    date: str
    title: str
    kind: str
    status: str
    evidence_level: str
    body: str
    technologies: tuple[str, ...] = field(default_factory=tuple)
    commits: tuple[str, ...] = field(default_factory=tuple)
    supersedes: tuple[str, ...] = field(default_factory=tuple)
    verified_by: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        for name in ("project", "date", "title", "kind", "body"):
            if not getattr(self, name).strip():
                raise RecordValidationError(f"HistoryRecord.{name} is required")
        if self.status not in RECORD_STATUSES:
            raise RecordValidationError(f"Unsupported record status: {self.status}")
        if self.evidence_level not in RECORD_EVIDENCE_LEVELS:
            raise RecordValidationError(
                f"Unsupported record evidence level: {self.evidence_level}"
            )

    @property
    def filename(self) -> str:
        return f"{self.date}-{_slug(self.title)}.md"

    def to_markdown(self) -> str:
        lines = [
            "---",
            f"project: {self.project}",
            f"date: {self.date}",
            f"type: {self.kind}",
            f"status: {self.status}",
            f"evidence_level: {self.evidence_level}",
            f"technologies: {_frontmatter_list(self.technologies)}",
            f"commits: {_frontmatter_list(self.commits)}",
            f"supersedes: {_frontmatter_list(self.supersedes)}",
            f"verified_by: {_frontmatter_list(self.verified_by)}",
            "---",
            "",
            f"# {self.title}",
            "",
            self.body.strip(),
            "",
        ]
        return "\n".join(lines)

    @classmethod
    def from_path(cls, path: Path) -> HistoryRecord:
        metadata, markdown_body = parse_frontmatter(path.read_text(encoding="utf-8"))
        if not metadata:
            raise RecordValidationError(f"Missing frontmatter: {path}")
        title = markdown_title(markdown_body, path.stem)
        return cls(
            project=str(metadata.get("project", "")),
            date=str(metadata.get("date", "")),
            title=title,
            kind=str(metadata.get("type", "history")),
            status=str(metadata.get("status", "")),
            evidence_level=str(metadata.get("evidence_level", "unknown")),
            body=_body_without_title(markdown_body),
            technologies=_string_tuple(metadata.get("technologies")),
            commits=_string_tuple(metadata.get("commits")),
            supersedes=_string_tuple(metadata.get("supersedes")),
            verified_by=_string_tuple(metadata.get("verified_by")),
        )


class RecordLifecycle:
    def __init__(self, *, local_root: Path, records_root: Path) -> None:
        self.local_root = local_root.resolve()
        self.records_root = records_root.resolve()
        self.candidates_root = self.local_root / "candidates"
        self.dispositions_root = self.local_root / "dispositions"

    def _candidate_path(self, candidate_id: str) -> Path:
        return self.candidates_root / f"{candidate_id}.json"

    def _disposition_path(self, candidate_id: str) -> Path:
        return self.dispositions_root / f"{candidate_id}.json"

    def queue(self, candidate: HistoryCandidate) -> Path:
        disposition = self._disposition_path(candidate.candidate_id)
        if disposition.exists():
            raise CandidateExcluded(
                f"Candidate {candidate.candidate_id} has a local disposition"
            )
        path = self._candidate_path(candidate.candidate_id)
        _atomic_write(
            path,
            json.dumps(candidate.to_mapping(), ensure_ascii=False, indent=2) + "\n",
        )
        return path

    def load_candidate(self, candidate_id: str) -> HistoryCandidate | None:
        path = self._candidate_path(candidate_id)
        if not path.exists():
            return None
        value = json.loads(path.read_text(encoding="utf-8"))
        return HistoryCandidate.from_mapping(value)

    def defer(self, candidate_id: str) -> HistoryCandidate:
        candidate = self.load_candidate(candidate_id)
        if candidate is None:
            raise FileNotFoundError(f"Candidate not found: {candidate_id}")
        return candidate

    def retain(
        self,
        candidate_id: str,
        record: HistoryRecord,
        *,
        verify: Callable[[Path], None],
    ) -> Path:
        candidate_path = self._candidate_path(candidate_id)
        candidate = self.load_candidate(candidate_id)
        if candidate is None:
            raise FileNotFoundError(f"Candidate not found: {candidate_id}")
        if record.project != candidate.project:
            raise RecordValidationError("Record project must match its Candidate")
        if not set(candidate.commits).issubset(record.commits):
            raise RecordValidationError("Record must preserve Candidate commits")

        record_path = self.records_root / record.filename
        if record_path.exists():
            raise FileExistsError(f"HistoryRecord already exists: {record_path}")

        _atomic_write(record_path, record.to_markdown())
        try:
            verify(record_path)
            candidate_path.unlink()
        except Exception:
            record_path.unlink(missing_ok=True)
            raise
        return record_path

    def exclude(
        self,
        candidate_id: str,
        *,
        reviewed_at: datetime | None = None,
    ) -> Path:
        candidate_path = self._candidate_path(candidate_id)
        if not candidate_path.exists():
            raise FileNotFoundError(f"Candidate not found: {candidate_id}")
        timestamp = reviewed_at or datetime.now(UTC)
        disposition_path = self._disposition_path(candidate_id)
        disposition = {
            "candidate_id": candidate_id,
            "disposition": "excluded",
            "reviewed_at": timestamp.isoformat(),
        }
        _atomic_write(
            disposition_path,
            json.dumps(disposition, ensure_ascii=False, indent=2) + "\n",
        )
        try:
            candidate_path.unlink()
        except Exception:
            disposition_path.unlink(missing_ok=True)
            raise
        return disposition_path
