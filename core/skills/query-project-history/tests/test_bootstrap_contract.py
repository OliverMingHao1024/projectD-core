from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

CORE = Path(__file__).parents[4]
SETUP = CORE / "scripts" / "setup-project-history.ps1"
SETUP_BAT = CORE / "scripts" / "setup.bat"
UNINSTALL_BAT = CORE / "scripts" / "uninstall.bat"


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
def test_lexical_bootstrap_is_offline_and_creates_runtime_config(
    tmp_path: Path,
) -> None:
    runtime = tmp_path / "project-history"
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(SETUP),
            "-PythonPath",
            sys.executable,
            "-Mode",
            "lexical",
            "-NonInteractive",
            "-RuntimeRoot",
            str(runtime),
        ],
        cwd=CORE,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    configuration = json.loads(
        (runtime / "runtime.json").read_text(encoding="utf-8")
    )
    assert configuration["mode"] == "lexical"
    assert "Mode：lexical" in result.stdout
    package_check = subprocess.run(
        [
            str(runtime / ".venv" / "Scripts" / "python.exe"),
            "-c",
            (
                "import importlib.util; "
                "raise SystemExit(1 if importlib.util.find_spec('fastembed') else 0)"
            ),
        ],
        check=False,
    )
    assert package_check.returncode == 0


def test_batch_entrypoints_do_not_bypass_execution_policy() -> None:
    for entrypoint in (SETUP_BAT, UNINSTALL_BAT):
        content = entrypoint.read_text(encoding="utf-8")
        assert "ExecutionPolicy" not in content
        assert "pwsh -NoProfile -File" in content


def test_hybrid_dependencies_are_fully_hash_locked() -> None:
    requirements = (
        CORE
        / "core"
        / "skills"
        / "query-project-history"
        / "scripts"
        / "requirements.txt"
    ).read_text(encoding="utf-8")
    package_lines = [
        line for line in requirements.splitlines() if line and not line.startswith("#")
    ]
    assert package_lines
    assert all("==" in line and "--hash=sha256:" in line for line in package_lines)
    setup = SETUP.read_text(encoding="utf-8")
    assert setup.count("'--require-hashes'") == 3


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
@pytest.mark.parametrize(
    "url, expected",
    [
        ("http://packages.example.test/simple", "HTTPS"),
        ("https://user:secret@packages.example.test/simple", "credentials"),
        ("https://packages.example.test/simple?token=secret", "credentials"),
    ],
)
def test_package_index_rejects_unsafe_urls(
    tmp_path: Path,
    url: str,
    expected: str,
) -> None:
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(SETUP),
            "-PythonPath",
            sys.executable,
            "-Mode",
            "lexical",
            "-NonInteractive",
            "-RuntimeRoot",
            str(tmp_path / "runtime"),
            "-PackageIndexUrl",
            url,
        ],
        cwd=CORE,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    assert result.returncode != 0
    assert expected in result.stderr
