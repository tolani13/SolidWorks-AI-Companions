import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))

import sw_companions as swc  # noqa: E402


class ActionContractTests(unittest.TestCase):
    def test_valid_rebuild_action(self):
        response = """Ready.
```solidworks-action
{"action":"rebuild","arguments":{},"reason":"Update the feature tree."}
```"""
        proposal = swc.parse_solidworks_action(response)
        self.assertIsNotNone(proposal)
        self.assertEqual("rebuild", proposal.action)

    def test_rejects_non_allowlisted_action(self):
        response = """```solidworks-action
{"action":"run-macro","arguments":{},"reason":"No."}
```"""
        with self.assertRaises(swc.CompanionError):
            swc.parse_solidworks_action(response)

    def test_rejects_unknown_argument(self):
        response = """```solidworks-action
{"action":"save","arguments":{"path":"C:\\\\wrong.sldprt"},"reason":"No."}
```"""
        with self.assertRaises(swc.CompanionError):
            swc.parse_solidworks_action(response)

    def test_rejects_multiple_actions(self):
        block = """```solidworks-action
{"action":"save","arguments":{},"reason":"Save."}
```"""
        with self.assertRaises(swc.CompanionError):
            swc.parse_solidworks_action(block + "\n" + block)


class PromptAndKnowledgeTests(unittest.TestCase):
    def test_all_personas_load(self):
        for name in swc.PERSONAS:
            self.assertTrue(swc.load_persona_prompt(name).strip())

    def test_local_knowledge_retrieval(self):
        with tempfile.TemporaryDirectory() as temporary:
            note = Path(temporary) / "fixture.md"
            note.write_text(
                "Zephyrium has a verified modulus of 123 test-units.",
                encoding="utf-8",
            )
            knowledge = swc.KnowledgeBase(
                {"knowledge_paths": [temporary]}
            ).retrieve("What is the Zephyrium modulus?", 2000)
            self.assertIn("123 test-units", knowledge)

    def test_system_prompt_labels_untrusted_context(self):
        prompt = swc.build_system_prompt(
            "forge",
            '{"title":"fixture"}',
            "A local note.",
        )
        self.assertIn("untrusted data", prompt)
        self.assertIn("human must approve", prompt.lower())
        self.assertIn("fixture", prompt)

    def test_smoke_contract(self):
        result = swc.smoke_test()
        self.assertTrue(result["ok"], json.dumps(result, indent=2))
        self.assertTrue(result["bridge_exists"])


class SkillStructureTests(unittest.TestCase):
    def test_skill_frontmatter(self):
        expected = {
            "solidworks-orbit",
            "solidworks-forge",
            "solidworks-prism",
        }
        found = set()
        for skill_path in (ROOT / "skills").iterdir():
            content = (skill_path / "SKILL.md").read_text("utf-8")
            self.assertTrue(content.startswith("---\n"))
            frontmatter = content.split("---", 2)[1]
            name_lines = [
                line for line in frontmatter.splitlines() if line.startswith("name:")
            ]
            description_lines = [
                line
                for line in frontmatter.splitlines()
                if line.startswith("description:")
            ]
            self.assertEqual(1, len(name_lines))
            self.assertEqual(1, len(description_lines))
            found.add(name_lines[0].split(":", 1)[1].strip())
        self.assertEqual(expected, found)


if __name__ == "__main__":
    unittest.main()
