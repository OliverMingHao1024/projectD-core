from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

CORE = Path(__file__).parents[1]
CONTRACT = CORE / "scripts" / "tests" / "governance-wiring.contract.ps1"


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
def test_governance_wiring_public_lifecycle(tmp_path: Path) -> None:
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(CONTRACT),
            "-TempRoot",
            str(tmp_path / "wiring"),
        ],
        cwd=CORE,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    assert "GOVERNANCE_WIRING_CONTRACT_OK" in result.stdout
