from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

CORE = Path(__file__).parents[1]
CONTRACT = CORE / "scripts" / "tests" / "governance-command-policy-hook.contract.ps1"


@pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell is unavailable")
def test_governance_command_policy_hook_contract() -> None:
    result = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-File",
            str(CONTRACT),
        ],
        cwd=CORE,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    for marker in (
        "[PASS] anonymous tunnel commands are blocked",
        "[PASS] TFS-style commands are blocked only on a confirmed GitHub remote",
        "[PASS] DevSpace MCP is denied unless the repository is registered personal",
        "[PASS] machine-level registration is a fallback that repo-level overrides",
        "[PASS] DevSpace lifecycle Bash commands (compose/cloudflared) are gated too",
        "[PASS] anonymous devtunnel is exempted only on a personal-registered repo/machine",
        "[PASS] anonymous-tunnel detection covers -a and access-create --anonymous too",
        "[PASS] devtunnel lifecycle commands (not just cloudflared) are gated too",
        "[PASS] registry never stores plaintext remote identifiers or hostnames",
        "[PASS] a fully-qualified tf.exe path is still detected",
        "[PASS] editing the registry file directly is blocked",
        "[PASS] a shell command writing to the registry file is blocked",
        "[PASS] a plain read of the registry file remains allowed",
        "[PASS] editing an unrelated file remains allowed",
        "[PASS] non-shell/non-DevSpace tools and PostToolUse are unaffected",
        "[PASS] malformed stdin fails open",
        "[PASS] registration requires a real interactive terminal, not a redirected-stdin call",
        "[PASS] Codex and Claude hook configs both wire the command policy hook",
    ):
        assert marker in result.stdout
