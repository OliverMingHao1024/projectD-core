from __future__ import annotations

import json
import unittest
from pathlib import Path


CORE = Path(__file__).parents[1]


def read_skill(name: str) -> str:
    return (CORE / "core" / "skills" / name / "SKILL.md").read_text(
        encoding="utf-8"
    )


class ImplementationReviewGateContractTests(unittest.TestCase):
    def test_code_review_supports_required_modes_and_degradation(self) -> None:
        content = read_skill("code-review")

        self.assertIn("Review only.", content)
        self.assertIn("**Working tree:**", content)
        self.assertIn("**Fixed point:**", content)
        self.assertIn("`No spec available`", content)
        self.assertIn("parallel execution is not", content)
        self.assertIn("`Review gate: passed`", content)
        self.assertIn("`Review gate: blocked`", content)

    def test_implement_requires_bounded_review_but_not_tdd(self) -> None:
        content = read_skill("implement")
        normalized = " ".join(content.split())

        self.assertIn("Prefer TDD when", content)
        self.assertIn("Do not require TDD", content)
        self.assertIn("Invoke the `code-review` Skill", content)
        self.assertIn("`code-review: not applicable`", content)
        self.assertIn("one focused re-review", content)
        self.assertIn("Do not create an unbounded review loop", normalized)
        self.assertIn("Do not commit, push", content)

    def test_both_skills_are_adopted_and_pinned(self) -> None:
        registry = json.loads(
            (CORE / "vault" / "governance" / "skill-registry.json").read_text(
                encoding="utf-8"
            )
        )
        candidates = {
            item["canonical_name"]: item
            for item in registry["candidates"]
            if item["canonical_name"]
        }

        for name in ("code-review", "implement"):
            candidate = candidates[name]
            self.assertEqual(candidate["lifecycle_status"], "adopted")
            self.assertEqual(candidate["migration_status"], "complete")
            self.assertTrue(candidate["observed_commit"])
            self.assertTrue(candidate["upstream_digest"].startswith("sha256:"))
            self.assertEqual(candidate["target"], f"core/skills/{name}")


if __name__ == "__main__":
    unittest.main()
