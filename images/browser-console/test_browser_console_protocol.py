from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("browser_console_protocol.py")
SPEC = importlib.util.spec_from_file_location("browser_console_protocol", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
browser_console_protocol = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = browser_console_protocol
SPEC.loader.exec_module(browser_console_protocol)


class RecordingStream:
    def __init__(self) -> None:
        self.writes: list[bytes] = []

    def write(self, payload: bytes) -> None:
        self.writes.append(payload)


class RfbStream:
    def __init__(self) -> None:
        self.responses = [
            b"RFB 003.008\n",
            b"\x01",
            b"\x02",
            b"0" * 16,
            b"\x00\x00\x00\x00",
            b"\x00\x01\x00\x01" + b"\x20" + b"\x00" * 15 + b"\x00\x00\x00\x00",
        ]
        self.closed = False

    def read_exact(self, size: int) -> bytes:
        if size == 0:
            return b""
        return self.responses.pop(0)

    def write(self, _payload: bytes) -> None:
        pass

    def close(self) -> None:
        self.closed = True


class BrowserProtocolTest(unittest.TestCase):
    def test_type_url_paces_keyboard_events(self) -> None:
        stream = RecordingStream()

        with patch.object(browser_console_protocol.time, "sleep") as sleep:
            browser_console_protocol._type_url(stream, "ab")

        self.assertEqual(
            [call.args[0] for call in sleep.call_args_list], [0.2, 0.02, 0.02, 0.2]
        )

    def test_authenticate_vnc_uses_configured_websocket_path(self) -> None:
        stream = RfbStream()

        with (
            patch.object(
                browser_console_protocol,
                "open_websocket",
                return_value=stream,
            ) as open_websocket,
            patch.object(
                browser_console_protocol,
                "_vnc_des_response",
                return_value=b"response",
            ),
        ):
            result = browser_console_protocol.authenticate_vnc(
                "172.31.1.162",
                443,
                "172.31.1.162",
                b"password",
                websocket_path="/noc-idc/websockify",
            )

        self.assertTrue(result.accepted)
        self.assertTrue(stream.closed)
        open_websocket.assert_called_once_with(
            "172.31.1.162",
            443,
            "172.31.1.162",
            path="/noc-idc/websockify",
            tls_context=None,
            server_hostname=None,
        )


if __name__ == "__main__":
    unittest.main()
