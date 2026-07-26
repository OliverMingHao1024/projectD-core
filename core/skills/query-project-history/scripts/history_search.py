from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Protocol

DEFAULT_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
ALLOWED_STATUSES = {
    "accepted",
    "rejected",
    "failed",
    "superseded",
    "experimental",
}
AUXILIARY_PATH = re.compile(
    r"(?ix)"
    r"(^|/)(docs/(specs?|requirements?|dev-log|verification|adr|decisions?|"
    r"incidents?|postmortems?|retros?)|README|CHANGELOG|AGENTS|CLAUDE)"
)
SECRET_PATH = re.compile(
    r"(?ix)(^|/)(\.env($|\.)|secrets?($|/)|credentials?($|/)|"
    r".*\.(pem|key|pfx|p12)$)"
)


class EmbeddingUnavailable(RuntimeError):
    pass


class Embedding(Protocol):
    name: str

    def embed_documents(self, texts: list[str]) -> list[list[float]]: ...

    def embed_query(self, text: str) -> list[float]: ...


class FastEmbedEmbedding:
    def __init__(self, model_name: str = DEFAULT_MODEL) -> None:
        try:
            from fastembed import TextEmbedding
        except ImportError as error:
            raise EmbeddingUnavailable(
                "Hybrid mode requires the local 'fastembed' package. "
                "Install it in an isolated environment before indexing."
            ) from error
        self.name = model_name
        self._model = TextEmbedding(model_name=model_name)

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [vector.tolist() for vector in self._model.embed(texts)]

    def embed_query(self, text: str) -> list[float]:
        vectors = list(self._model.query_embed([text]))
        return vectors[0].tolist()


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(db_path)
    connection.row_factory = sqlite3.Row
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS documents (
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
        );
        CREATE UNIQUE INDEX IF NOT EXISTS documents_source
            ON documents(project, source, title);
        CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
            document_id UNINDEXED,
            title,
            content,
            tokenize='unicode61'
        );
        """
    )
    return connection


def parse_frontmatter(text: str) -> tuple[dict[str, object], str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}, text
    metadata: dict[str, object] = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        value = raw_value.strip()
        if value.startswith("[") and value.endswith("]"):
            metadata[key.strip()] = [
                item.strip().strip("'\"")
                for item in value[1:-1].split(",")
                if item.strip()
            ]
        else:
            metadata[key.strip()] = value.strip("'\"")
    return metadata, text[end + 5 :]


def markdown_title(body: str, fallback: str) -> str:
    for line in body.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return fallback


def cjk_bigrams(text: str) -> str:
    groups = re.findall(r"[\u3400-\u9fff]+", text)
    return " ".join(
        group[index : index + 2] for group in groups for index in range(len(group) - 1)
    )


def git(repo: Path, arguments: Sequence[str]) -> str:
    result = subprocess.run(
        [
            "git",
            "-c",
            f"safe.directory={repo.resolve()}",
            "-c",
            "core.quotepath=false",
            "-C",
            str(repo),
            *arguments,
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.stdout


def history_documents(repo: Path) -> list[dict[str, str]]:
    root = repo / "docs" / "history"
    if not root.exists():
        return []
    documents: list[dict[str, str]] = []
    for path in sorted(root.glob("*.md")):
        metadata, body = parse_frontmatter(path.read_text(encoding="utf-8"))
        status = str(metadata.get("status", "experimental"))
        if status not in ALLOWED_STATUSES:
            status = "experimental"
        documents.append(
            {
                "project": str(metadata.get("project", repo.name)),
                "kind": str(metadata.get("type", "history")),
                "status": status,
                "date": str(metadata.get("date", "")),
                "source": str(path.resolve()),
                "title": markdown_title(body, path.stem),
                "content": body.strip(),
            }
        )
    return documents


def auxiliary_documents(repo: Path, commit_limit: int = 300) -> list[dict[str, str]]:
    documents: list[dict[str, str]] = []
    try:
        tracked = git(repo, ["ls-files"]).splitlines()
    except subprocess.CalledProcessError:
        return documents
    for relative in tracked:
        normalized = relative.replace("\\", "/")
        if (
            not normalized.lower().endswith(".md")
            or SECRET_PATH.search(normalized)
            or "/licenses/" in normalized.lower()
            or not AUXILIARY_PATH.search(normalized)
        ):
            continue
        path = repo / relative
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        _, body = parse_frontmatter(text)
        documents.append(
            {
                "project": repo.name,
                "kind": "document",
                "status": "experimental",
                "date": "",
                "source": str(path.resolve()),
                "title": markdown_title(body, path.stem),
                "content": body[:20_000].strip(),
            }
        )
    format_string = "%H%x1f%ad%x1f%s%x1f%b%x1e"
    try:
        log = git(
            repo,
            [
                "log",
                f"--max-count={commit_limit}",
                "--date=short",
                f"--pretty=format:{format_string}",
            ],
        )
    except subprocess.CalledProcessError:
        return documents
    for record in log.split("\x1e"):
        fields = record.strip().split("\x1f")
        if len(fields) not in (3, 4):
            continue
        commit, date, subject = fields[:3]
        body = fields[3] if len(fields) == 4 else ""
        documents.append(
            {
                "project": repo.name,
                "kind": "commit",
                "status": "experimental",
                "date": date,
                "source": f"git:{repo.resolve()}@{commit}",
                "title": subject,
                "content": f"{subject}\n{body}".strip(),
            }
        )
    return documents


def index_project(
    db_path: Path,
    repo: Path,
    *,
    include_auxiliary: bool,
    embedding: Embedding | None = None,
) -> int:
    repo = repo.resolve()
    documents = history_documents(repo)
    if include_auxiliary:
        documents.extend(auxiliary_documents(repo))
    vectors: list[list[float] | None]
    if embedding and documents:
        vectors = list(
            embedding.embed_documents(
                [f"{item['title']}\n{item['content']}" for item in documents]
            )
        )
    else:
        vectors = [None] * len(documents)
    connection = connect(db_path)
    project_names = {repo.name, *(item["project"] for item in documents)}
    with connection:
        for project_name in project_names:
            ids = [
                row[0]
                for row in connection.execute(
                    "SELECT id FROM documents WHERE project = ?", (project_name,)
                )
            ]
            connection.executemany(
                "DELETE FROM documents_fts WHERE document_id = ?",
                [(item_id,) for item_id in ids],
            )
            connection.execute(
                "DELETE FROM documents WHERE project = ?", (project_name,)
            )
        for item, vector in zip(documents, vectors, strict=True):
            cursor = connection.execute(
                """
                INSERT INTO documents(
                    project, kind, status, date, source, title, content,
                    vector, embedding_model
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item["project"],
                    item["kind"],
                    item["status"],
                    item["date"],
                    item["source"],
                    item["title"],
                    item["content"],
                    json.dumps(vector) if vector is not None else None,
                    embedding.name if embedding else None,
                ),
            )
            connection.execute(
                "INSERT INTO documents_fts(document_id, title, content) VALUES (?, ?, ?)",
                (
                    cursor.lastrowid,
                    item["title"],
                    f"{item['content']}\n{cjk_bigrams(item['title'] + ' ' + item['content'])}",
                ),
            )
    connection.close()
    return len(documents)


def fts_query(text: str) -> str:
    tokens = re.findall(r"[\w.-]+", text, flags=re.UNICODE)
    tokens.extend(cjk_bigrams(text).split())
    return " OR ".join(f'"{token.replace(chr(34), "")}"' for token in tokens)


def cosine(left: list[float], right: list[float]) -> float:
    numerator = sum(a * b for a, b in zip(left, right, strict=True))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if not left_norm or not right_norm:
        return 0.0
    return numerator / (left_norm * right_norm)


def search(
    db_path: Path,
    query: str,
    *,
    mode: str,
    limit: int,
    embedding: Embedding | None = None,
    project: str | None = None,
) -> list[dict[str, object]]:
    if mode == "hybrid" and embedding is None:
        raise EmbeddingUnavailable(
            "Hybrid search requires an embedding backend; it will not silently "
            "fall back to lexical search."
        )
    connection = connect(db_path)
    lexical_rows: list[sqlite3.Row] = []
    match = fts_query(query)
    if match:
        sql = """
                SELECT d.*, bm25(documents_fts) AS lexical_score
                FROM documents_fts
                JOIN documents d ON d.id = documents_fts.document_id
                WHERE documents_fts MATCH ?
        """
        parameters: list[object] = [match]
        if project:
            sql += " AND d.project = ?"
            parameters.append(project)
        sql += " ORDER BY lexical_score LIMIT 100"
        lexical_rows = list(connection.execute(sql, parameters))
    if project:
        all_rows = list(
            connection.execute("SELECT * FROM documents WHERE project = ?", (project,))
        )
    else:
        all_rows = list(connection.execute("SELECT * FROM documents"))
    combined: dict[int, dict[str, object]] = {}
    for rank, row in enumerate(lexical_rows, start=1):
        item = dict(row)
        item["score"] = 1.0 / (60 + rank)
        item["vector_score"] = 0.0
        combined[row["id"]] = item
    if mode == "hybrid":
        assert embedding is not None
        query_vector = embedding.embed_query(query)
        vector_rows: list[tuple[float, sqlite3.Row]] = []
        for row in all_rows:
            if not row["vector"]:
                continue
            vector = json.loads(row["vector"])
            if len(vector) != len(query_vector):
                continue
            vector_rows.append((cosine(query_vector, vector), row))
        if not vector_rows and all_rows:
            raise EmbeddingUnavailable(
                "The index has no compatible vectors. Re-index it in hybrid mode."
            )
        vector_rows.sort(key=lambda pair: pair[0], reverse=True)
        for rank, (vector_score, row) in enumerate(vector_rows[:100], start=1):
            item = combined.setdefault(row["id"], dict(row))
            item["score"] = float(item.get("score", 0.0)) + 1.0 / (60 + rank)
            item["vector_score"] = vector_score
    results = sorted(
        combined.values(), key=lambda item: float(item["score"]), reverse=True
    )[:limit]
    for item in results:
        item.pop("vector", None)
        item.pop("embedding_model", None)
        item.pop("id", None)
        item.pop("lexical_score", None)
    connection.close()
    return results


def git_candidates(repo: Path, limit: int) -> list[dict[str, object]]:
    format_string = "%H%x1f%ad%x1f%s%x1e"
    output = git(
        repo,
        [
            "log",
            f"--max-count={limit}",
            "--date=short",
            f"--pretty=format:{format_string}",
        ],
    )
    candidates: list[dict[str, object]] = []
    for record in output.split("\x1e"):
        fields = record.strip().split("\x1f")
        if len(fields) != 3:
            continue
        commit, date, subject = fields
        candidates.append(
            {
                "project": repo.name,
                "date": date,
                "title": subject,
                "type": classify_commit(subject),
                "status": "experimental",
                "commits": [commit],
                "needs_review": True,
                "warning": "Git alone cannot prove root cause or failed attempts.",
            }
        )
    return candidates


def classify_commit(subject: str) -> str:
    lowered = subject.lower()
    if re.search(r"\b(fix|bug|hotfix)\b|修正|錯誤|異常", lowered):
        return "bug"
    if re.search(r"\b(refactor|architecture|design)\b|重構|架構|設計", lowered):
        return "refactor"
    if re.search(r"\b(feat|feature)\b|新增|實作", lowered):
        return "decision"
    return "experiment"


def print_results(results: list[dict[str, object]], as_json: bool) -> None:
    if as_json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return
    if not results:
        print("No matching evidence found.")
        return
    for index, item in enumerate(results, start=1):
        print(
            f"{index}. [{item['status']}] {item['project']} — {item['title']}\n"
            f"   {item['source']}"
        )


def evaluate(
    db_path: Path,
    benchmark_path: Path,
    *,
    mode: str,
    limit: int,
    embedding: Embedding | None = None,
) -> dict[str, object]:
    questions = json.loads(benchmark_path.read_text(encoding="utf-8"))
    cases: list[dict[str, object]] = []
    hits = 0
    for question in questions:
        results = search(
            db_path,
            str(question["query"]),
            mode=mode,
            limit=limit,
            embedding=embedding,
            project=question.get("project"),
        )
        expected_values = question["expected"]
        if isinstance(expected_values, str):
            expected_values = [expected_values]
        expected = [str(value).lower() for value in expected_values]
        rank = next(
            (
                index
                for index, result in enumerate(results, start=1)
                if any(value in str(result["source"]).lower() for value in expected)
            ),
            None,
        )
        if rank is not None:
            hits += 1
        cases.append(
            {
                "query": question["query"],
                "expected": question["expected"],
                "rank": rank,
                "top_sources": [result["source"] for result in results],
            }
        )
    total = len(questions)
    return {
        "mode": mode,
        "limit": limit,
        "hits": hits,
        "total": total,
        "hit_rate": hits / total if total else 0.0,
        "cases": cases,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Search local project history")
    subparsers = parser.add_subparsers(dest="command", required=True)

    index = subparsers.add_parser("index")
    index.add_argument("--db", type=Path, required=True)
    index.add_argument("--project", type=Path, action="append", required=True)
    index.add_argument("--include-auxiliary", action="store_true")
    index.add_argument("--mode", choices=("lexical", "hybrid"), default="lexical")
    index.add_argument("--model", default=DEFAULT_MODEL)

    query = subparsers.add_parser("query")
    query.add_argument("--db", type=Path, required=True)
    query.add_argument("--query", required=True)
    query.add_argument("--mode", choices=("lexical", "hybrid"), default="lexical")
    query.add_argument("--model", default=DEFAULT_MODEL)
    query.add_argument("--limit", type=int, default=5)
    query.add_argument("--project")
    query.add_argument("--json", action="store_true")

    candidates = subparsers.add_parser("candidates")
    candidates.add_argument("--project", type=Path, required=True)
    candidates.add_argument("--limit", type=int, default=10)
    candidates.add_argument("--output", type=Path)

    evaluation = subparsers.add_parser("evaluate")
    evaluation.add_argument("--db", type=Path, required=True)
    evaluation.add_argument("--benchmark", type=Path, required=True)
    evaluation.add_argument("--mode", choices=("lexical", "hybrid"), default="lexical")
    evaluation.add_argument("--model", default=DEFAULT_MODEL)
    evaluation.add_argument("--limit", type=int, default=5)
    evaluation.add_argument("--output", type=Path)
    return parser


def main(arguments: list[str] | None = None) -> int:
    args = build_parser().parse_args(arguments)
    try:
        if args.command == "index":
            embedding = (
                FastEmbedEmbedding(args.model) if args.mode == "hybrid" else None
            )
            total = 0
            for project in args.project:
                total += index_project(
                    args.db,
                    project,
                    include_auxiliary=args.include_auxiliary,
                    embedding=embedding,
                )
            print(f"Indexed {total} records into {args.db}")
            return 0
        if args.command == "query":
            embedding = (
                FastEmbedEmbedding(args.model) if args.mode == "hybrid" else None
            )
            results = search(
                args.db,
                args.query,
                mode=args.mode,
                limit=args.limit,
                embedding=embedding,
                project=args.project,
            )
            print_results(results, args.json)
            return 0
        if args.command == "evaluate":
            embedding = (
                FastEmbedEmbedding(args.model) if args.mode == "hybrid" else None
            )
            report = evaluate(
                args.db,
                args.benchmark,
                mode=args.mode,
                limit=args.limit,
                embedding=embedding,
            )
            output = json.dumps(report, ensure_ascii=False, indent=2)
            if args.output:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(output + "\n", encoding="utf-8")
            else:
                print(output)
            return 0
        candidates = git_candidates(args.project.resolve(), args.limit)
        output = json.dumps(candidates, ensure_ascii=False, indent=2)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(output + "\n", encoding="utf-8")
        else:
            print(output)
        return 0
    except (EmbeddingUnavailable, subprocess.CalledProcessError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
