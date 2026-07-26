from __future__ import annotations

import json
import os
import sqlite3
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

from history_search import (
    DEFAULT_MODEL,
    Embedding,
    FastEmbedEmbedding,
    GitReader,
    SubprocessGitReader,
    connect,
    git_candidates,
    index_project,
    index_status,
    search,
)
from project_history_records import (
    CandidateExcluded,
    HistoryCandidate,
    HistoryRecord,
    RecordLifecycle,
)

RUNTIME_SCHEMA_VERSION = 1
PROJECTS_SCHEMA_VERSION = 1
RUNTIME_MODES = frozenset({"lexical", "hybrid"})


class RuntimeConfigurationError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class RuntimePaths:
    root: Path
    database: Path
    models: Path
    logs: Path
    projects_config: Path
    runtime_config: Path

    @classmethod
    def from_root(cls, root: Path) -> RuntimePaths:
        resolved = root.resolve()
        return cls(
            root=resolved,
            database=resolved / "index.db",
            models=resolved / "models",
            logs=resolved / "logs",
            projects_config=resolved / "projects.json",
            runtime_config=resolved / "runtime.json",
        )


@dataclass(frozen=True, slots=True)
class RuntimeSettings:
    mode: str
    model: str

    def __post_init__(self) -> None:
        if self.mode not in RUNTIME_MODES:
            raise RuntimeConfigurationError(f"Unsupported runtime mode: {self.mode}")
        if not self.model.strip():
            raise RuntimeConfigurationError("Runtime model is required")

    def to_mapping(self) -> dict[str, object]:
        return {
            "schema_version": RUNTIME_SCHEMA_VERSION,
            "mode": self.mode,
            "model": self.model,
        }


@dataclass(frozen=True, slots=True)
class ProjectConfig:
    name: str
    path: Path
    include_auxiliary: bool = False

    def to_mapping(self) -> dict[str, object]:
        return {
            "name": self.name,
            "path": str(self.path),
            "include_auxiliary": self.include_auxiliary,
        }


@dataclass(frozen=True, slots=True)
class QueryResponse:
    mode: str
    results: list[dict[str, object]]


EmbeddingFactory = Callable[[RuntimeSettings], Embedding]


def _atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temporary.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class LocalHistoryRuntime:
    def __init__(
        self,
        *,
        core_root: Path,
        runtime_root: Path,
        embedding_factory: EmbeddingFactory | None = None,
        git_reader: GitReader | None = None,
    ) -> None:
        self.core_root = core_root.resolve()
        self.paths = RuntimePaths.from_root(runtime_root)
        self.embedding_factory = embedding_factory or self._default_embedding
        self.git_reader = git_reader or SubprocessGitReader()

    def _default_embedding(self, settings: RuntimeSettings) -> Embedding:
        return FastEmbedEmbedding(
            settings.model,
            cache_dir=self.paths.models,
            allow_download=False,
        )

    def _load_settings(self) -> RuntimeSettings:
        if not self.paths.runtime_config.exists():
            settings = RuntimeSettings(mode="hybrid", model=DEFAULT_MODEL)
            _atomic_json(self.paths.runtime_config, settings.to_mapping())
            return settings
        value = json.loads(self.paths.runtime_config.read_text(encoding="utf-8"))
        if value.get("schema_version") != RUNTIME_SCHEMA_VERSION:
            raise RuntimeConfigurationError(
                "Unsupported runtime.json schema_version: "
                f"{value.get('schema_version')}"
            )
        return RuntimeSettings(
            mode=str(value.get("mode", "")),
            model=str(value.get("model", DEFAULT_MODEL)),
        )

    def _save_settings(self, settings: RuntimeSettings) -> None:
        _atomic_json(self.paths.runtime_config, settings.to_mapping())

    def _load_projects(self) -> list[ProjectConfig]:
        if not self.paths.projects_config.exists():
            _atomic_json(
                self.paths.projects_config,
                {"schema_version": PROJECTS_SCHEMA_VERSION, "projects": []},
            )
            return []
        value = json.loads(self.paths.projects_config.read_text(encoding="utf-8"))
        if value.get("schema_version") != PROJECTS_SCHEMA_VERSION:
            raise RuntimeConfigurationError(
                "Unsupported projects.json schema_version: "
                f"{value.get('schema_version')}"
            )
        projects: list[ProjectConfig] = []
        for entry in value.get("projects", []):
            name = str(entry.get("name", ""))
            path = Path(str(entry.get("path", ""))).resolve()
            if not name or not str(entry.get("path", "")):
                raise RuntimeConfigurationError(
                    "Each allowlist entry requires name and path"
                )
            if path.name.casefold() != name.casefold():
                raise RuntimeConfigurationError(
                    f"Allowlist name must match directory name: {path.name}"
                )
            projects.append(
                ProjectConfig(
                    name=name,
                    path=path,
                    include_auxiliary=bool(entry.get("include_auxiliary", False)),
                )
            )
        return projects

    def _save_projects(self, projects: list[ProjectConfig]) -> None:
        _atomic_json(
            self.paths.projects_config,
            {
                "schema_version": PROJECTS_SCHEMA_VERSION,
                "projects": [project.to_mapping() for project in projects],
            },
        )

    def list_projects(self) -> list[ProjectConfig]:
        return self._load_projects()

    def add_project(
        self,
        path: Path,
        *,
        include_auxiliary: bool = False,
    ) -> ProjectConfig:
        resolved = path.resolve()
        if not resolved.is_dir():
            raise RuntimeConfigurationError(f"Project directory does not exist: {path}")
        project = ProjectConfig(
            name=resolved.name,
            path=resolved,
            include_auxiliary=include_auxiliary,
        )
        projects = self._load_projects()
        for existing in projects:
            if existing.name.casefold() == project.name.casefold():
                if existing == project:
                    return existing
                raise RuntimeConfigurationError(
                    f"Project name already points to another configuration: {project.name}"
                )
        projects.append(project)
        projects.sort(key=lambda item: item.name.casefold())
        self._save_projects(projects)
        return project

    def remove_project(self, name: str) -> ProjectConfig:
        projects = self._load_projects()
        for project in projects:
            if project.name.casefold() == name.casefold():
                self._save_projects(
                    [item for item in projects if item.name != project.name]
                )
                return project
        raise RuntimeConfigurationError(f"Project is not allowlisted: {name}")

    def _project(self, name: str) -> ProjectConfig:
        for project in self._load_projects():
            if project.name.casefold() == name.casefold():
                return project
        raise RuntimeConfigurationError(f"Project is not allowlisted: {name}")

    def _lifecycle(self, records_root: Path | None = None) -> RecordLifecycle:
        return RecordLifecycle(
            local_root=self.paths.root,
            records_root=records_root or self.core_root / "docs" / "history",
        )

    def scan_candidates(
        self,
        project_name: str,
        *,
        limit: int = 10,
    ) -> list[HistoryCandidate]:
        project = self._project(project_name)
        records_root = project.path / "docs" / "history"
        lifecycle = self._lifecycle(records_root)
        recorded_commits = {
            commit
            for path in records_root.glob("*.md")
            for commit in HistoryRecord.from_path(path).commits
        }
        queued: list[HistoryCandidate] = []
        for mapping in git_candidates(
            project.path,
            limit,
            git_reader=self.git_reader,
        ):
            candidate = HistoryCandidate.from_mapping(mapping)
            if recorded_commits.intersection(candidate.commits):
                continue
            try:
                lifecycle.queue(candidate)
            except CandidateExcluded:
                continue
            queued.append(candidate)
        return queued

    def list_candidates(self) -> list[HistoryCandidate]:
        return self._lifecycle().list_candidates()

    def defer_candidate(self, candidate_id: str) -> HistoryCandidate:
        return self._lifecycle().defer(candidate_id)

    def exclude_candidate(self, candidate_id: str) -> Path:
        return self._lifecycle().exclude(candidate_id)

    def retain_candidate(self, candidate_id: str, record_draft: Path) -> Path:
        record = HistoryRecord.from_path(record_draft)
        project = self._project(record.project)
        lifecycle = self._lifecycle(project.path / "docs" / "history")

        def verify(_: Path) -> None:
            self._verify_project_record_index(project)

        return lifecycle.retain(candidate_id, record, verify=verify)

    def _verify_project_record_index(self, project: ProjectConfig) -> None:
        settings = self._load_settings()
        embedding = self._embedding(settings)
        self.paths.root.mkdir(parents=True, exist_ok=True)
        temporary = self.paths.root / f"record.verify-{uuid.uuid4().hex}.db"
        derived = (temporary, Path(f"{temporary}-wal"), Path(f"{temporary}-shm"))
        try:
            index_project(
                temporary,
                project.path,
                include_auxiliary=project.include_auxiliary,
                embedding=embedding,
                git_reader=self.git_reader,
            )
            self._write_index_metadata(temporary, settings)
            self._validate_index(temporary, settings)
        finally:
            for path in derived:
                path.unlink(missing_ok=True)

    def set_mode(self, mode: str) -> RuntimeSettings:
        current = self._load_settings()
        updated = RuntimeSettings(mode=mode, model=current.model)
        self._save_settings(updated)
        return updated

    def _index_mode(self) -> str | None:
        if not self.paths.database.exists():
            return None
        connection = sqlite3.connect(self.paths.database)
        try:
            row = connection.execute(
                "SELECT value FROM runtime_metadata WHERE key = 'mode'"
            ).fetchone()
        except sqlite3.OperationalError:
            return None
        finally:
            connection.close()
        return str(row[0]) if row else None

    def status(self) -> dict[str, object]:
        settings = self._load_settings()
        projects = self._load_projects()
        status = index_status(self.paths.database)
        status.update(
            {
                "mode": settings.mode,
                "model": settings.model,
                "index_mode": self._index_mode(),
                "allowlist_count": len(projects),
                "runtime_root": str(self.paths.root),
            }
        )
        return status

    def _embedding(self, settings: RuntimeSettings) -> Embedding | None:
        if settings.mode == "lexical":
            return None
        return self.embedding_factory(settings)

    def _write_index_metadata(
        self,
        database: Path,
        settings: RuntimeSettings,
    ) -> None:
        connection = connect(database)
        with connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS runtime_metadata (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """
            )
            connection.execute(
                "INSERT OR REPLACE INTO runtime_metadata(key, value) VALUES ('mode', ?)",
                (settings.mode,),
            )
            connection.execute(
                "INSERT OR REPLACE INTO runtime_metadata(key, value) VALUES ('model', ?)",
                (settings.model,),
            )
        connection.close()

    def _validate_index(
        self,
        database: Path,
        settings: RuntimeSettings,
    ) -> None:
        connection = sqlite3.connect(database)
        try:
            integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
            mode = connection.execute(
                "SELECT value FROM runtime_metadata WHERE key = 'mode'"
            ).fetchone()[0]
        finally:
            connection.close()
        if integrity != "ok":
            raise RuntimeError(f"Temporary index failed integrity check: {integrity}")
        if mode != settings.mode:
            raise RuntimeError(
                f"Temporary index mode mismatch: expected {settings.mode}, got {mode}"
            )

    def rebuild(self) -> dict[str, object]:
        settings = self._load_settings()
        projects = self._load_projects()
        if not projects:
            raise RuntimeConfigurationError(
                "The project allowlist is empty; add a project before rebuilding"
            )
        embedding = self._embedding(settings)
        self.paths.root.mkdir(parents=True, exist_ok=True)
        temporary = self.paths.root / f"index.next-{uuid.uuid4().hex}.db"
        derived = (temporary, Path(f"{temporary}-wal"), Path(f"{temporary}-shm"))
        try:
            for project in projects:
                index_project(
                    temporary,
                    project.path,
                    include_auxiliary=project.include_auxiliary,
                    embedding=embedding,
                    git_reader=self.git_reader,
                )
            self._write_index_metadata(temporary, settings)
            self._validate_index(temporary, settings)
            os.replace(temporary, self.paths.database)
        finally:
            for path in derived:
                path.unlink(missing_ok=True)
        return self.status()

    def update(self) -> dict[str, object]:
        return self.rebuild()

    def query(
        self,
        text: str,
        *,
        project: str | None = None,
        limit: int = 5,
    ) -> QueryResponse:
        if not text.strip():
            raise RuntimeConfigurationError("Query text cannot be empty")
        if not self.paths.database.exists():
            raise RuntimeConfigurationError("The index does not exist; rebuild it first")
        settings = self._load_settings()
        index_mode = self._index_mode()
        if index_mode and index_mode != settings.mode:
            raise RuntimeConfigurationError(
                "The configured mode differs from the index; rebuild before querying"
            )
        results = search(
            self.paths.database,
            text,
            mode=settings.mode,
            limit=limit,
            embedding=self._embedding(settings),
            project=project,
        )
        return QueryResponse(mode=settings.mode, results=results)

    def record_operation(
        self,
        command: str,
        *,
        success: bool,
        elapsed_ms: int,
        error_type: str = "",
    ) -> Path:
        self.paths.logs.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(UTC)
        path = self.paths.logs / (
            f"{timestamp.strftime('%Y-%m-%d-%H%M%S-%f')}-{os.getpid()}.jsonl"
        )
        record = {
            "timestamp_utc": timestamp.isoformat(),
            "command": command,
            "success": success,
            "elapsed_ms": elapsed_ms,
            "error_type": error_type,
        }
        path.write_text(
            json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        self._rotate_operation_logs(timestamp)
        return path

    def _rotate_operation_logs(self, now: datetime) -> None:
        files = sorted(
            self.paths.logs.glob("*.jsonl"),
            key=lambda path: path.stat().st_mtime,
        )
        cutoff = now - timedelta(days=7)
        for path in files:
            modified = datetime.fromtimestamp(path.stat().st_mtime, tz=UTC)
            if modified < cutoff:
                path.unlink(missing_ok=True)
        files = sorted(
            self.paths.logs.glob("*.jsonl"),
            key=lambda path: path.stat().st_mtime,
        )
        total = sum(path.stat().st_size for path in files)
        while len(files) > 1 and total > 10 * 1024 * 1024:
            oldest = files.pop(0)
            total -= oldest.stat().st_size
            oldest.unlink(missing_ok=True)
