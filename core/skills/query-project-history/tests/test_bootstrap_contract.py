from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

CORE = Path(__file__).parents[4]
SETUP = CORE / "scripts" / "setup-project-history.ps1"


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
