from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

CORE = Path(__file__).parents[1]
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def read_skill(name: str, resource: str = "SKILL.md") -> str:
    return (CORE / "core" / "skills" / name / resource).read_text(
        encoding="utf-8"
    )


class MattPocockSkillUpdateContractTests(unittest.TestCase):
    def test_diagnosing_bugs_redacts_sensitive_evidence(self) -> None:
        content = read_skill("diagnosing-bugs")

        self.assertIn("<REDACTED>", content)
        self.assertIn("credentials in environment variables", content)
        self.assertIn("redacted captured artifact", content)
        self.assertIn("redacted output", content)

    def test_logic_prototype_routes_by_audience(self) -> None:
        entrypoint = read_skill("prototype")
        logic = read_skill("prototype", "LOGIC.md")

        self.assertIn("project-native terminal app", entrypoint)
        self.assertIn("self-contained HTML file", entrypoint)
        self.assertIn("Choose from the audience and handoff need", logic)
        self.assertIn("Project-native terminal app", logic)
        self.assertIn("Self-contained HTML file", logic)
        self.assertIn("no framework, bundler, server", logic)

    def test_registry_tracks_reviewed_upstream_and_questionnaire_move(self) -> None:
        registry = json.loads(
            (CORE / "vault" / "governance" / "skill-registry.json").read_text(
                encoding="utf-8"
            )
        )
        source = next(
            item
            for item in registry["sources"]
            if item["id"] == "github-mattpocock-skills"
        )
        candidates = {
            item["canonical_name"]: item
            for item in registry["candidates"]
            if item["source_id"] == source["id"] and item["canonical_name"]
        }

        questionnaire = candidates["to-questionnaire"]
        self.assertEqual(
            questionnaire["id"],
            "mattpocock-skills--skills-productivity-to-questionnaire",
        )
        self.assertEqual(
            questionnaire["source_path"],
            "skills/productivity/to-questionnaire",
        )

        # Freshness is skill-update-check's job (it recomputes the digest live
        # against upstream via skill-scout). A candidate's observed commit
        # legitimately differs from the source's latest bookmark: an unchanged
        # Skill keeps the commit it was last reviewed at, and an adopted update
        # moves only that candidate. So this test checks only that the recorded
        # evidence is well-formed, and hardcodes no commit or digest hex that
        # would rot on the next normal import.
        self.assertRegex(
            source["latest_observed_commit"],
            COMMIT_PATTERN,
            "source latest_observed_commit is not a full commit SHA",
        )
        adopted = {
            name: candidate
            for name, candidate in candidates.items()
            if candidate["lifecycle_status"] == "adopted"
        }
        for name, candidate in adopted.items():
            self.assertIsNotNone(
                candidate["observed_commit"], f"{name}: missing observed_commit"
            )
            self.assertRegex(
                candidate["observed_commit"],
                COMMIT_PATTERN,
                f"{name}: observed_commit is not a full commit SHA",
            )
            self.assertRegex(
                candidate["upstream_digest"],
                DIGEST_PATTERN,
                f"{name}: upstream_digest is not a well-formed sha256 digest",
            )


if __name__ == "__main__":
    unittest.main()
