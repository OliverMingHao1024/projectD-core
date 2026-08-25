from __future__ import annotations

import json
import unittest
from pathlib import Path


CORE = Path(__file__).parents[1]
UPSTREAM_COMMIT = "6654f6b60cd9d5be8b54c6fafe44346dabeb3b76"
WRITING_GREAT_SKILLS_COMMIT = "ed37663cc5fbef691ddfecd080dff42f7e7e350d"


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

        self.assertEqual(source["latest_observed_commit"], UPSTREAM_COMMIT)

        questionnaire = candidates["to-questionnaire"]
        self.assertEqual(
            questionnaire["id"],
            "mattpocock-skills--skills-productivity-to-questionnaire",
        )
        self.assertEqual(
            questionnaire["source_path"],
            "skills/productivity/to-questionnaire",
        )
        self.assertEqual(questionnaire["observed_commit"], UPSTREAM_COMMIT)
        self.assertEqual(
            questionnaire["upstream_digest"],
            "sha256:b22edeef084d7b0b3fae02fbe50116ea1e2c2dfa87169f3a4170bb2d0270e079",
        )

        self.assertEqual(
            candidates["writing-great-skills"]["observed_commit"],
            WRITING_GREAT_SKILLS_COMMIT,
        )
        for name, candidate in candidates.items():
            if name != "writing-great-skills":
                self.assertEqual(candidate["observed_commit"], UPSTREAM_COMMIT)


if __name__ == "__main__":
    unittest.main()
