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
                {
                    "id": 1,
                    "result": {"result": {"type": "string", "value": "visible"}},
                },
                {"id": 1, "result": {}},
                {
                    "method": "Security.visibleSecurityStateChanged",
                    "params": {"visibleSecurityState": {"securityState": "secure"}},
                },
            ]
        )
        target = {
            "id": "visible",
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
            [
                {
                    "id": 1,
                    "method": "Runtime.evaluate",
                    "params": {
                        "expression": "document.visibilityState",
                        "returnByValue": True,
                    },
                },
                {"id": 2, "method": "Security.enable"},
            ],
        )
        self.assertTrue(stream.closed)

    def test_ignores_a_hidden_matching_target(self) -> None:
        hidden = FakeStream(
            [
                {
                    "id": 1,
                    "result": {"result": {"type": "string", "value": "hidden"}},
                }
            ]
        )
        visible = FakeStream(
            [
                {
                    "id": 1,
                    "result": {"result": {"type": "string", "value": "visible"}},
                },
                {"id": 2, "result": {}},
                {
                    "method": "Security.visibleSecurityStateChanged",
                    "params": {"visibleSecurityState": {"securityState": "secure"}},
                },
            ]
        )
        targets = [
            {
                "id": "hidden",
                "type": "page",
                "url": "https://console.noc-idc.test/",
                "webSocketDebuggerUrl": "ws://127.0.0.1/devtools/page/hidden",
            },
            {
                "id": "visible",
                "type": "page",
                "url": "https://console.noc-idc.test/",
                "webSocketDebuggerUrl": "ws://127.0.0.1/devtools/page/visible",
            },
        ]

        with (
            patch.object(policy_probe, "page_targets", return_value=targets),
            patch.object(
                policy_probe,
                "target_stream",
                side_effect=[hidden, visible],
            ),
        ):
            self.assertTrue(policy_probe.endpoint_secure(9222, "console.noc-idc.test"))

        self.assertEqual(
            hidden.commands,
            [
                {
                    "id": 1,
                    "method": "Runtime.evaluate",
                    "params": {
                        "expression": "document.visibilityState",
                        "returnByValue": True,
                    },
                }
            ],
        )
        self.assertTrue(hidden.closed)

    def test_failure_reports_the_observed_target_state(self) -> None:
        stream = FakeStream(
            [
                {
                    "id": 1,
                    "result": {"result": {"type": "string", "value": "hidden"}},
                },
                {
                    "method": "Security.visibleSecurityStateChanged",
                    "params": {"visibleSecurityState": {"securityState": "insecure"}},
                },
            ]
        )
        target = {
            "id": "hidden",
            "type": "page",
            "url": "https://console.noc-idc.test/",
            "webSocketDebuggerUrl": "ws://127.0.0.1/devtools/page/hidden",
        }

        with (
            patch.object(policy_probe, "page_targets", return_value=[target]),
            patch.object(policy_probe, "target_stream", return_value=stream),
            patch.object(policy_probe.time, "monotonic", side_effect=[0, 0, 16]),
            patch.object(policy_probe.time, "sleep"),
            self.assertRaisesRegex(
                policy_probe.PolicyProbeError,
                "id=hidden.*visibility=hidden",
            ),
        ):
            policy_probe.endpoint_secure(9222, "console.noc-idc.test")


class PolicyTargetLifecycleTest(unittest.TestCase):
    def test_closes_the_temporary_policy_target_and_restores_the_visible_target(
        self,
    ) -> None:
        previous_target = {
            "id": "console",
            "type": "page",
            "url": "https://console.noc-idc.test/",
            "webSocketDebuggerUrl": "ws://127.0.0.1/devtools/page/console",
        }
        target = {
            "id": "policy",
            "type": "page",
            "url": "chrome://policy/",
            "webSocketDebuggerUrl": "ws://127.0.0.1/devtools/page/policy",
        }
        stream = FakeStream([])
        value = {
            "loaded": True,
            "expectedValue": True,
            "platform": True,
            "machine": True,
            "mandatory": True,
            "ok": True,
        }

        with (
            patch.object(policy_probe, "policy_certificate", return_value="cert"),
            patch.object(policy_probe, "encoded_certificate", return_value="cert"),
            patch.object(
                policy_probe,
                "visible_page_target",
                create=True,
                return_value=previous_target,
            ) as visible_page_target,
            patch.object(policy_probe, "create_target", return_value=target),
            patch.object(policy_probe, "target_stream", return_value=stream),
            patch.object(
                policy_probe,
                "cdp_call",
                return_value={"result": {"value": value}},
            ),
            patch.object(policy_probe, "close_target", create=True) as close_target,
            patch.object(
                policy_probe,
                "activate_target",
                create=True,
            ) as activate_target,
        ):
            self.assertTrue(policy_probe.policy_ok(9222, Path("/ca.crt")))

        visible_page_target.assert_called_once_with(9222)
        close_target.assert_called_once_with(9222, target)
        activate_target.assert_called_once_with(9222, previous_target)
        self.assertTrue(stream.closed)


if __name__ == "__main__":
    unittest.main()
