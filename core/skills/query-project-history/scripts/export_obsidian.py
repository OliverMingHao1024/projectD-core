from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import quote

WARNING = (
    "> [!warning] 未確認的歷程候選\n"
    "> 本頁內容由 Git 與專案文件回溯推導，狀態均為 `experimental`。"
    "人工確認前，不得視為已驗證事實或推薦方案。\n"
)
TYPE_LABELS = {
    "bug": "錯誤修正",
    "decision": "技術決策",
    "experiment": "實驗",
    "refactor": "重構",
}
STATUS_LABELS = {
    "accepted": "已採用",
    "rejected": "已否決",
    "failed": "失敗",
    "superseded": "已取代",
    "experimental": "待確認",
}


def file_link(path: Path, label: str) -> str:
    uri = "file:///" + quote(path.resolve().as_posix(), safe="/:")
    return f"[{label}]({uri})"


def evidence_link(project_root: Path, evidence: str, remote: str | None = None) -> str:
    if evidence.startswith("commit:"):
        commit = evidence.removeprefix("commit:")
        if remote:
            return f"[`{commit[:12]}`]({remote.rstrip('/')}/commit/{commit})"
        return f"`{commit[:12]}`"
    path = project_root / evidence
    return file_link(path, evidence)


def render_project(
    project: str,
    entries: list[dict[str, object]],
    project_root: Path,
    remote: str | None = None,
) -> str:
    lines = [
        "---",
        "tags: [project-history, experimental]",
        f"project: {project}",
        "---",
        "",
        f"# {project} 歷程候選",
        "",
        WARNING.rstrip(),
        "",
        "[[00-project-history-dashboard|← 回到總覽]]",
        "",
    ]
    for index, entry in enumerate(entries, start=1):
        status = str(entry["status"])
        entry_type = str(entry["type"])
        lines.extend(
            [
                f"## {index}. {entry['title']}",
                "",
                f"- 狀態：{STATUS_LABELS.get(status, status)}（`{status}`）",
                f"- 類型：{TYPE_LABELS.get(entry_type, entry_type)}",
                "- 證據："
                + "、".join(
                    evidence_link(project_root, str(item), remote)
                    for item in entry["evidence"]  # type: ignore[union-attr]
                ),
                "- 待確認：",
            ]
        )
        lines.extend(
            f"  - [ ] {question}"
            for question in entry["review"]  # type: ignore[union-attr]
        )
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_dashboard(
    projects: dict[str, list[dict[str, object]]],
    lexical: dict[str, object],
    hybrid: dict[str, object],
) -> str:
    lines = [
        "---",
        "tags: [project-history, dashboard]",
        "---",
        "",
        "# ProjectD 開發歷程",
        "",
        WARNING.rstrip(),
        "",
        "## 專案",
        "",
    ]
    for project, entries in projects.items():
        lines.append(f"- [[{project}-history|{project}]]：{len(entries)} 筆待審候選")
    lines.extend(
        [
            "",
            "## 概念驗證評測",
            "",
            (
                f"- 關鍵字檢索前五名：{lexical['hits']}/{lexical['total']} "
                f"（{float(lexical['hit_rate']):.0%}）"
            ),
            (
                f"- 混合檢索前五名：{hybrid['hits']}/{hybrid['total']} "
                f"（{float(hybrid['hit_rate']):.0%}）"
            ),
            "- [[retrieval-evaluation|查看 20 題結果]]",
            "",
            "## 狀態說明",
            "",
            "- `accepted`：已採用並驗證",
            "- `rejected`：評估後否決",
            "- `failed`：實作或驗證失敗",
            "- `superseded`：已被新方案取代",
            "- `experimental`：尚未人工確認",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def render_evaluation(lexical: dict[str, object], hybrid: dict[str, object]) -> str:
    lexical_cases = {
        str(case["query"]): case
        for case in lexical["cases"]  # type: ignore[union-attr]
    }
    lines = [
        "---",
        "tags: [project-history, evaluation]",
        "---",
        "",
        "# 歷程檢索評測",
        "",
        "[[00-project-history-dashboard|← 回到總覽]]",
        "",
        f"- 關鍵字檢索前五名：{lexical['hits']}/{lexical['total']}",
        f"- 混合檢索前五名：{hybrid['hits']}/{hybrid['total']}",
        "",
        "| # | 問題 | 關鍵字檢索 | 混合檢索 |",
        "|---:|---|:---:|:---:|",
    ]
    for index, case in enumerate(hybrid["cases"], start=1):  # type: ignore[union-attr]
        query = str(case["query"])
        safe_query = query.replace("|", "\\|")
        lexical_rank = lexical_cases[query]["rank"]
        hybrid_rank = case["rank"]
        lines.append(
            f"| {index} | {safe_query} | {lexical_rank or '—'} | {hybrid_rank or '—'} |"
        )
    return "\n".join(lines).rstrip() + "\n"


def export(
    candidates_path: Path,
    lexical_path: Path,
    hybrid_path: Path,
    output_dir: Path,
    project_roots: dict[str, Path],
    remotes: dict[str, str] | None = None,
) -> list[Path]:
    candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
    lexical = json.loads(lexical_path.read_text(encoding="utf-8"))
    hybrid = json.loads(hybrid_path.read_text(encoding="utf-8"))
    projects = candidates["projects"]
    output_dir.mkdir(parents=True, exist_ok=True)
    files = {
        output_dir / "00-project-history-dashboard.md": render_dashboard(
            projects, lexical, hybrid
        ),
        output_dir / "retrieval-evaluation.md": render_evaluation(lexical, hybrid),
    }
    for project, entries in projects.items():
        files[output_dir / f"{project}-history.md"] = render_project(
            project,
            entries,
            project_roots[project],
            (remotes or {}).get(project),
        )
    for path, content in files.items():
        path.write_text(content, encoding="utf-8")
    return list(files)


def main() -> int:
    parser = argparse.ArgumentParser(description="Export project history to Obsidian")
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--lexical-results", type=Path, required=True)
    parser.add_argument("--hybrid-results", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--project",
        action="append",
        required=True,
        help="Project mapping in name=path form",
    )
    parser.add_argument(
        "--remote",
        action="append",
        default=[],
        help="Optional web repository mapping in name=https://... form",
    )
    args = parser.parse_args()
    roots = {
        name: Path(path)
        for name, path in (mapping.split("=", 1) for mapping in args.project)
    }
    remotes = {
        name: url.removesuffix(".git")
        for name, url in (mapping.split("=", 1) for mapping in args.remote)
    }
    paths = export(
        args.candidates,
        args.lexical_results,
        args.hybrid_results,
        args.output,
        roots,
        remotes,
    )
    print(f"Exported {len(paths)} Markdown files to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
