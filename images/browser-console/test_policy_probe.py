from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("policy-probe.py")
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("policy_probe", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
policy_probe = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = policy_probe
SPEC.loader.exec_module(policy_probe)


class FakeStream:
    def __init__(self, messages: list[dict[str, object]]) -> None:
        self.messages = [json.dumps(message).encode() for message in messages]
        self.commands: list[dict[str, object]] = []
        self.closed = False

    def write_text(self, payload: str) -> None:
        self.commands.append(json.loads(payload))

    def read_message(self) -> tuple[int, bytes]:
        return 0x1, self.messages.pop(0)

    def close(self) -> None:
        self.closed = True


class EndpointSecurityTest(unittest.TestCase):
    def test_reads_visible_security_state_from_the_chromium_event(self) -> None:
        stream = FakeStream(
            [
                {"id": 1, "result": {}},
                {
                    "method": "Security.visibleSecurityStateChanged",
                    "params": {"visibleSecurityState": {"securityState": "secure"}},
                },
            ]
        )
        target = {
            "type": "page",
            "url": "https://console.noc-idc.test/",
            "webSocketDebuggerUrl": "ws://127.0.0.1/devtools/page/1",
        }

        with (
            patch.object(policy_probe, "page_targets", return_value=[target]),
            patch.object(policy_probe, "target_stream", return_value=stream),
        ):
            self.assertTrue(policy_probe.endpoint_secure(9222, "console.noc-idc.test"))

        self.assertEqual(
            stream.commands,
            [{"id": 1, "method": "Security.enable"}],
        )
        self.assertTrue(stream.closed)


if __name__ == "__main__":
    unittest.main()
