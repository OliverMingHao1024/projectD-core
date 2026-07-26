from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

CLI_SPEC = importlib.util.spec_from_file_location(
    "project_history_cli",
    SCRIPTS / "project_history_cli.py",
)
assert CLI_SPEC and CLI_SPEC.loader
cli = importlib.util.module_from_spec(CLI_SPEC)
sys.modules[CLI_SPEC.name] = cli
CLI_SPEC.loader.exec_module(cli)


def roots(tmp_path: Path) -> tuple[Path, Path]:
    core = tmp_path / "projectD-core"
    runtime = core / ".local" / "project-history"
    core.mkdir()
    return core, runtime


def base_arguments(core: Path, runtime: Path) -> list[str]:
    return [
        "--core-root",
        str(core),
        "--runtime-root",
        str(runtime),
    ]


def test_project_add_requires_explicit_confirmation(
    tmp_path: Path,
    capsys: object,
) -> None:
    core, runtime = roots(tmp_path)
    project = tmp_path / "sample"
    project.mkdir()

    exit_code = cli.main(
        [
            *base_arguments(core, runtime),
            "project",
            "add",
            str(project),
        ]
    )

    assert exit_code == 3
    assert "requires --yes" in capsys.readouterr().err  # type: ignore[attr-defined]
    config = json.loads((runtime / "projects.json").read_text(encoding="utf-8"))
    assert config["projects"] == []


def test_project_add_and_list_use_runtime_interface(
    tmp_path: Path,
    capsys: object,
) -> None:
    core, runtime = roots(tmp_path)
    project = tmp_path / "sample"
    project.mkdir()

    assert (
        cli.main(
            [
                *base_arguments(core, runtime),
                "project",
                "add",
                str(project),
                "--yes",
            ]
        )
        == 0
    )
    capsys.readouterr()  # type: ignore[attr-defined]
    assert (
        cli.main(
            [
                *base_arguments(core, runtime),
                "project",
                "list",
            ]
        )
        == 0
    )
    listed = json.loads(capsys.readouterr().out)  # type: ignore[attr-defined]

    assert listed == [
        {
            "name": "sample",
            "path": str(project.resolve()),
            "include_auxiliary": False,
        }
    ]


def test_query_output_always_reports_active_mode(
    tmp_path: Path,
    capsys: object,
) -> None:
    core, runtime_root = roots(tmp_path)
    project = tmp_path / "sample"
    history = project / "docs" / "history"
    history.mkdir(parents=True)
    (history / "record.md").write_text(
        """---
project: sample
date: 2026-07-27
type: decision
status: accepted
evidence_level: verified
---
# Local history

Local history stays on this device.
""",
        encoding="utf-8",
    )
    runtime = cli.LocalHistoryRuntime(core_root=core, runtime_root=runtime_root)
    runtime.set_mode("lexical")
    runtime.add_project(project)
    runtime.rebuild()

    exit_code = cli.main(
        [
            *base_arguments(core, runtime_root),
            "query",
            "local history",
            "--json",
        ]
    )
    output = json.loads(capsys.readouterr().out)  # type: ignore[attr-defined]

    assert exit_code == 0
    assert output["mode"] == "lexical"
    assert output["results"][0]["project"] == "sample"
    logs = list((runtime_root / "logs").glob("*.jsonl"))
    assert logs
    serialized_logs = "\n".join(
        path.read_text(encoding="utf-8") for path in logs
    )
    assert "local history" not in serialized_logs
    assert '"command":"query"' in serialized_logs
