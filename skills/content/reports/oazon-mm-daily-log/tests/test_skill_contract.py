from __future__ import annotations

import unittest
from pathlib import Path


SKILL = Path(__file__).parents[1] / "SKILL.md"


class SkillContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw = SKILL.read_bytes()
        cls.text = cls.raw.decode("utf-8")

    def test_main_skill_stays_compact(self) -> None:
        self.assertLessEqual(len(self.text.splitlines()), 100)
        self.assertLessEqual(len(self.raw), 6144)

    def test_safety_and_quality_rules_remain_visible(self) -> None:
        required = (
            "只写本人",
            "完整读",
            "约 8h",
            "30 字",
            "真实",
            "Boost",
            "备份",
            "diff",
            "用户确认",
            "只读",
        )
        for phrase in required:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.text)

    def test_references_are_loaded_only_when_needed(self) -> None:
        for reference in (
            "references/report-format.md",
            "references/mattermost-api.md",
            "references/daily-md.md",
        ):
            with self.subTest(reference=reference):
                self.assertIn(reference, self.text)
        self.assertIn("仅在", self.text)
        self.assertIn("按需", self.text)


if __name__ == "__main__":
    unittest.main()
