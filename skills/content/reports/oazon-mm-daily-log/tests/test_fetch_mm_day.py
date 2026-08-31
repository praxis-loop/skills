from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "scripts" / "fetch_mm_day.py"
SPEC = importlib.util.spec_from_file_location("fetch_mm_day", SCRIPT)
assert SPEC and SPEC.loader
FETCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FETCH)


class ResolveOpenCliCommandTests(unittest.TestCase):
    def test_windows_uses_node_entry_instead_of_cmd_shim(self) -> None:
        resolver = getattr(FETCH, "resolve_opencli_command", None)
        self.assertIsNotNone(resolver, "缺少 resolve_opencli_command")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            node = root / "node.exe"
            shim = root / "opencli.cmd"
            entry = (
                root
                / "node_modules"
                / "@jackwener"
                / "opencli"
                / "dist"
                / "src"
                / "main.js"
            )
            entry.parent.mkdir(parents=True)
            node.touch()
            shim.touch()
            entry.touch()

            paths = {"node": str(node), "opencli.cmd": str(shim)}
            command = resolver("nt", paths.get)

        self.assertEqual(command, [str(node), str(entry)])
        self.assertNotIn("opencli.cmd", command)

    def test_posix_uses_opencli_from_path(self) -> None:
        resolver = getattr(FETCH, "resolve_opencli_command", None)
        self.assertIsNotNone(resolver, "缺少 resolve_opencli_command")

        command = resolver("posix", {"opencli": "/usr/local/bin/opencli"}.get)

        self.assertEqual(command, ["/usr/local/bin/opencli"])

    def test_runner_decodes_utf8_output(self) -> None:
        runner = getattr(FETCH, "run_opencli", None)
        self.assertIsNotNone(runner, "缺少 run_opencli")

        prefix = [sys.executable, "-X", "utf8", "-c", "print('→ 已完成')"]
        with mock.patch.object(FETCH, "resolve_opencli_command", return_value=prefix):
            result = runner([], timeout=10)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "→ 已完成")


class ExistingBehaviorTests(unittest.TestCase):
    def test_asia_shanghai_day_bounds_are_stable(self) -> None:
        since, until, date_str = FETCH.day_bounds_ms("2026-08-31", 8)

        self.assertEqual(date_str, "2026-08-31")
        self.assertEqual(until - since, 86_400_000)
        self.assertEqual(
            datetime.fromtimestamp(since / 1000, timezone.utc).isoformat(),
            "2026-08-30T16:00:00+00:00",
        )

    def test_extract_payload_keeps_first_json_line(self) -> None:
        output = "warning\n{\"ok\": true}\nmore noise\n"
        self.assertEqual(FETCH.extract_payload(output), '{"ok": true}')


if __name__ == "__main__":
    unittest.main()
