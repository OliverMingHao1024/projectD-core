from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from history_search import EmbeddingUnavailable, print_results
from project_history_runtime import (
    LocalHistoryRuntime,
    RuntimeConfigurationError,
)


def build_parser() -> argparse.ArgumentParser:
    default_core = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description="Manage local project history")
    parser.add_argument("--core-root", type=Path, default=default_core)
    parser.add_argument("--runtime-root", type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status")
    subparsers.add_parser("rebuild")
    subparsers.add_parser("update")

    query = subparsers.add_parser("query")
    query.add_argument("text")
    query.add_argument("--project")
    query.add_argument("--limit", type=int, default=5)
    query.add_argument("--json", action="store_true")

    mode = subparsers.add_parser("mode")
    mode.add_argument("value", choices=("lexical", "hybrid"))

    project = subparsers.add_parser("project")
    project_commands = project.add_subparsers(dest="project_command", required=True)
    project_commands.add_parser("list")

    add = project_commands.add_parser("add")
    add.add_argument("path", type=Path)
    add.add_argument("--include-auxiliary", action="store_true")
    add.add_argument("--yes", action="store_true")

    remove = project_commands.add_parser("remove")
    remove.add_argument("name")
    remove.add_argument("--yes", action="store_true")

    candidate = subparsers.add_parser("candidate")
    candidate_commands = candidate.add_subparsers(
        dest="candidate_command",
        required=True,
    )
    candidate_commands.add_parser("list")

    scan = candidate_commands.add_parser("scan")
    scan.add_argument("project")
    scan.add_argument("--limit", type=int, default=10)

    defer = candidate_commands.add_parser("defer")
    defer.add_argument("candidate_id")

    exclude = candidate_commands.add_parser("exclude")
    exclude.add_argument("candidate_id")
    exclude.add_argument("--yes", action="store_true")

    retain = candidate_commands.add_parser("retain")
    retain.add_argument("candidate_id")
    retain.add_argument("--record", type=Path, required=True)
    retain.add_argument("--yes", action="store_true")
    return parser


def _print_json(value: object) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def main(arguments: list[str] | None = None) -> int:
    args = build_parser().parse_args(arguments)
    runtime_root = args.runtime_root or args.core_root / ".local" / "project-history"
    runtime = LocalHistoryRuntime(
        core_root=args.core_root,
        runtime_root=runtime_root,
    )
    started = time.perf_counter()
    exit_code = 2
    error_type = ""
    try:
        if args.command == "status":
            _print_json(runtime.status())
            exit_code = 0
        elif args.command == "rebuild":
            _print_json(runtime.rebuild())
            exit_code = 0
        elif args.command == "update":
            _print_json(runtime.update())
            exit_code = 0
        elif args.command == "mode":
            _print_json(runtime.set_mode(args.value).to_mapping())
            exit_code = 0
        elif args.command == "query":
            response = runtime.query(
                args.text,
                project=args.project,
                limit=args.limit,
            )
            if args.json:
                _print_json({"mode": response.mode, "results": response.results})
            else:
                print(f"[mode: {response.mode}]")
                print_results(response.results, False)
            exit_code = 0
        elif args.command == "candidate":
            if args.candidate_command == "list":
                _print_json(
                    [
                        candidate.to_mapping()
                        for candidate in runtime.list_candidates()
                    ]
                )
                exit_code = 0
            elif args.candidate_command == "scan":
                _print_json(
                    [
                        candidate.to_mapping()
                        for candidate in runtime.scan_candidates(
                            args.project,
                            limit=args.limit,
                        )
                    ]
                )
                exit_code = 0
            elif args.candidate_command == "defer":
                _print_json(
                    runtime.defer_candidate(args.candidate_id).to_mapping()
                )
                exit_code = 0
            elif not args.yes:
                print(
                    f"candidate {args.candidate_command} requires --yes after review",
                    file=sys.stderr,
                )
                error_type = "ConfirmationRequired"
                exit_code = 3
            elif args.candidate_command == "exclude":
                _print_json(
                    {
                        "disposition": str(
                            runtime.exclude_candidate(args.candidate_id)
                        )
                    }
                )
                exit_code = 0
            else:
                _print_json(
                    {
                        "record": str(
                            runtime.retain_candidate(
                                args.candidate_id,
                                args.record,
                            )
                        )
                    }
                )
                exit_code = 0
        elif args.project_command == "list":
            _print_json(
                [project.to_mapping() for project in runtime.list_projects()]
            )
            exit_code = 0
        else:
            runtime.list_projects()
            if not args.yes:
                print(
                    f"project {args.project_command} requires --yes after review",
                    file=sys.stderr,
                )
                error_type = "ConfirmationRequired"
                exit_code = 3
            elif args.project_command == "add":
                _print_json(
                    runtime.add_project(
                        args.path,
                        include_auxiliary=args.include_auxiliary,
                    ).to_mapping()
                )
                exit_code = 0
            else:
                _print_json(runtime.remove_project(args.name).to_mapping())
                exit_code = 0
    except (
        EmbeddingUnavailable,
        RuntimeConfigurationError,
        RuntimeError,
        OSError,
        ValueError,
    ) as error:
        error_type = type(error).__name__
        print(f"error: {error}", file=sys.stderr)
        exit_code = 2
    finally:
        elapsed_ms = round((time.perf_counter() - started) * 1000)
        try:
            runtime.record_operation(
                args.command,
                success=exit_code == 0,
                elapsed_ms=elapsed_ms,
                error_type=error_type,
            )
        except OSError as log_error:
            print(f"warning: operation log failed: {log_error}", file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
