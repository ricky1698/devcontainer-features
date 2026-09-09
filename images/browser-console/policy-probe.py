#!/usr/bin/env python3
"""Inspect the visible Chromium through its loopback DevTools endpoint."""

from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import cast

from browser_console_protocol import (
    BrowserProtocolError,
    WebSocketStream,
    open_websocket,
)

JsonValue = None | bool | int | float | str | list["JsonValue"] | dict[str, "JsonValue"]
JsonObject = dict[str, JsonValue]
POLICY_FILE = Path("/etc/chromium/policies/managed/ca-certificates.json")
DEVTOOLS_PORT = 9222
COOKIE_NAME = "browser_console_replacement_probe"
COOKIE_URL = os.environ.get("BROWSER_START_URL", "https://browser-console.test/")


class PolicyProbeError(RuntimeError):
    pass


def json_object(value: JsonValue, context: str) -> JsonObject:
    if not isinstance(value, dict):
        raise PolicyProbeError(f"Expected a JSON object for {context}")
    return value


def json_objects(value: JsonValue, context: str) -> list[JsonObject]:
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise PolicyProbeError(f"Expected a JSON object list for {context}")
    return cast(list[JsonObject], value)


def string_value(value: JsonValue, context: str) -> str:
    if not isinstance(value, str):
        raise PolicyProbeError(f"Expected a string for {context}")
    return value


def policy_certificate() -> str:
    policy = json_object(cast(JsonValue, json.loads(POLICY_FILE.read_text())), "policy")
    certificates = policy.get("CACertificates")
    if not isinstance(certificates, list) or len(certificates) != 1:
        raise PolicyProbeError("CACertificates must contain exactly one certificate")
    return string_value(certificates[0], "CACertificates value")


def encoded_certificate(path: Path) -> str:
    certificate = ssl.PEM_cert_to_DER_cert(path.read_text())
    return base64.b64encode(certificate).decode()


def wait_for_debugger() -> int:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            json_object(
                load_json(f"http://127.0.0.1:{DEVTOOLS_PORT}/json/version"),
                "DevTools version",
            )
            return DEVTOOLS_PORT
        except (OSError, PolicyProbeError, ValueError):
            pass
        time.sleep(0.1)
    raise PolicyProbeError("Visible Chromium DevTools endpoint did not become ready")


def load_json(url: str, *, method: str = "GET") -> JsonValue:
    request = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(request, timeout=5) as response:
        return cast(JsonValue, json.load(response))


def page_targets(port: int) -> list[JsonObject]:
    targets = json_objects(
        load_json(f"http://127.0.0.1:{port}/json/list"), "DevTools targets"
    )
    return [target for target in targets if target.get("type") == "page"]


def create_target(port: int, url: str) -> JsonObject:
    target_url = urllib.parse.quote(url, safe="")
    return json_object(
        load_json(f"http://127.0.0.1:{port}/json/new?{target_url}", method="PUT"),
        "DevTools target",
    )


def target_stream(port: int, target: JsonObject) -> WebSocketStream:
    websocket_url = string_value(
        target.get("webSocketDebuggerUrl"), "target WebSocket URL"
    )
    parsed = urllib.parse.urlsplit(websocket_url)
    return open_websocket(
        "127.0.0.1",
        port,
        f"127.0.0.1:{port}",
        path=parsed.path,
        subprotocol=None,
    )


def cdp_call(
    stream: WebSocketStream,
    identifier: int,
    method: str,
    params: JsonObject | None = None,
) -> JsonObject:
    command: JsonObject = {"id": identifier, "method": method}
    if params is not None:
        command["params"] = params
    stream.write_text(json.dumps(command))
    while True:
        opcode, payload = stream.read_message()
        if opcode != 0x1:
            continue
        response = json_object(
            cast(JsonValue, json.loads(payload)), "DevTools response"
        )
        if response.get("id") != identifier:
            continue
        if "error" in response:
            raise PolicyProbeError(f"DevTools {method} failed: {response['error']}")
        return json_object(response.get("result"), f"DevTools {method} result")


def policy_ok(port: int, ca_file: Path) -> bool:
    expected = policy_certificate()
    if expected != encoded_certificate(ca_file):
        raise PolicyProbeError(
            "Chromium CACertificates policy does not match the mounted CA"
        )
    target = create_target(port, "chrome://policy")
    stream = target_stream(port, target)
    expression = f"""(() => {{
      const rows = [];
      const collect = (root) => {{
        for (const element of root.querySelectorAll('*')) {{
          if (element.tagName === 'POLICY-ROW') rows.push(element);
          if (element.shadowRoot) collect(element.shadowRoot);
        }}
      }};
      collect(document);
      const policy = rows
        .map((element) => element.policy)
        .find((item) => item && item.name === 'CACertificates');
      return {{
        loaded: Boolean(policy),
        expectedValue: Array.isArray(policy?.value) &&
          policy.value.length === 1 && policy.value[0] === {json.dumps(expected)},
        platform: policy?.source === 'platform',
        machine: policy?.scope === 'machine',
        mandatory: policy?.level === 'mandatory',
        ok: policy?.status === 'OK',
        source: policy?.source || '',
        scope: policy?.scope || '',
        level: policy?.level || '',
        status: policy?.status || '',
      }};
    }})()"""
    try:
        value: JsonObject = {}
        for identifier in range(1, 31):
            result = cdp_call(
                stream,
                identifier,
                "Runtime.evaluate",
                {"expression": expression, "returnByValue": True},
            )
            remote = json_object(result.get("result"), "remote value")
            value = json_object(remote.get("value"), "policy result")
            if all(
                value.get(field) is True
                for field in (
                    "loaded",
                    "expectedValue",
                    "platform",
                    "machine",
                    "mandatory",
                    "ok",
                )
            ):
                return True
            time.sleep(0.25)
        raise PolicyProbeError(
            f"Chromium policy fields did not match: {json.dumps(value, sort_keys=True)}"
        )
    finally:
        stream.close()


def endpoint_secure(port: int, hostname: str) -> bool:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        target = next(
            (
                item
                for item in page_targets(port)
                if string_value(item.get("url"), "target URL").startswith(
                    f"https://{hostname}/"
                )
            ),
            None,
        )
        if target is None:
            time.sleep(0.25)
            continue
        stream = target_stream(port, target)
        try:
            result = cdp_call(stream, 1, "Security.getVisibleSecurityState")
            visible = json_object(
                result.get("visibleSecurityState"), "visible security state"
            )
            if visible.get("securityState") == "secure":
                return True
        finally:
            stream.close()
        time.sleep(0.25)
    return False


def cookie_present(port: int) -> bool:
    targets = page_targets(port)
    if not targets:
        raise PolicyProbeError("Visible Chromium has no page target")
    stream = target_stream(port, targets[0])
    try:
        result = cdp_call(stream, 1, "Network.getAllCookies")
        cookies = json_objects(result.get("cookies"), "Chromium cookies")
        return any(cookie.get("name") == COOKIE_NAME for cookie in cookies)
    finally:
        stream.close()


def set_cookie(port: int) -> None:
    targets = page_targets(port)
    if not targets:
        raise PolicyProbeError("Visible Chromium has no page target")
    stream = target_stream(port, targets[0])
    try:
        result = cdp_call(
            stream,
            1,
            "Network.setCookie",
            {
                "name": COOKIE_NAME,
                "value": "present",
                "url": COOKIE_URL,
                "secure": True,
                "sameSite": "Strict",
            },
        )
        if result.get("success") is not True:
            raise PolicyProbeError("Chromium refused the replacement probe cookie")
    finally:
        stream.close()
    if not cookie_present(port):
        raise PolicyProbeError("Chromium did not retain the replacement probe cookie")


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__)
    subcommands = command.add_subparsers(dest="command", required=True)
    policy = subcommands.add_parser("policy")
    policy.add_argument("--ca-file", type=Path, required=True)
    endpoint = subcommands.add_parser("endpoint")
    endpoint.add_argument("hostname")
    subcommands.add_parser("set-cookie")
    subcommands.add_parser("assert-cookie-absent")
    return command


def main() -> int:
    args = parser().parse_args()
    port = wait_for_debugger()
    if args.command == "policy":
        if not policy_ok(port, cast(Path, args.ca_file)):
            raise PolicyProbeError(
                "Chromium did not report CACertificates as Platform/Machine/Mandatory/OK"
            )
        print("Chromium CACertificates runtime policy: PASS")
    elif args.command == "endpoint":
        hostname = cast(str, args.hostname)
        if not endpoint_secure(port, hostname):
            raise PolicyProbeError(f"Visible Chromium did not securely open {hostname}")
        print(f"Visible Chromium endpoint {hostname}: PASS")
    elif args.command == "set-cookie":
        set_cookie(port)
        print("Chromium replacement probe cookie: SET")
    elif args.command == "assert-cookie-absent":
        if cookie_present(port):
            raise PolicyProbeError("Chromium retained the previous Pod's probe cookie")
        print("Chromium replacement probe cookie: ABSENT")
    else:
        raise PolicyProbeError(f"Unknown command {args.command}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BrowserProtocolError, PolicyProbeError, OSError, ValueError) as exc:
        raise SystemExit(str(exc)) from exc
