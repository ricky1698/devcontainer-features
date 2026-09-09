# /// script
# requires-python = ">=3.11"
# ///
"""Exercise the browser console image through its network and process boundaries."""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import cast

from browser_console_protocol import (
    BrowserProtocolError,
    authenticate_vnc,
)

PORT = 16080


class SmokeTestError(RuntimeError):
    pass


def run(
    argv: list[str],
    *,
    check: bool = True,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        argv,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise SmokeTestError(f"{argv[0]} failed: {detail}")
    return result


def docker_run_args(
    name: str, image: str, work: Path, *, include_ca: bool
) -> list[str]:
    arguments = [
        "docker",
        "run",
        "--detach",
        "--name",
        name,
        "--read-only",
        "--cap-drop",
        "ALL",
        "--cap-add",
        "SETGID",
        "--cap-add",
        "SETUID",
        "--cap-add",
        "SYS_ADMIN",
        "--cap-add",
        "SYS_CHROOT",
        "--tmpfs",
        "/home/browser:rw,uid=0,gid=10001,mode=0770",
        "--tmpfs",
        "/run/browser-console:rw,uid=0,gid=10001,mode=0770",
        "--tmpfs",
        "/tmp:rw,uid=10001,gid=10001,mode=1777",
        "--tmpfs",
        "/dev/shm:rw,uid=10001,gid=10001,mode=1777,size=2g",
        "--mount",
        f"type=bind,src={work / 'password'},dst=/run/secrets/vnc/password,readonly",
        "--env",
        "BROWSER_START_URL=https://browser-console.test/",
        "--publish",
        f"127.0.0.1:{PORT}:6080",
    ]
    if include_ca:
        arguments.extend(
            [
                "--tmpfs",
                "/etc/chromium/policies/managed:rw,uid=10001,gid=10001,mode=0770",
                "--mount",
                f"type=bind,src={work / 'ca.crt'},dst=/run/browser-console-ca/ca.crt,readonly",
                "--env",
                "BROWSER_CA_FILE=/run/browser-console-ca/ca.crt",
            ]
        )
    arguments.append(image)
    return arguments


def wait_for_novnc(name: str) -> str:
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        status = run(
            ["docker", "inspect", "--format", "{{.State.Running}}", name]
        ).stdout.strip()
        if status != "true":
            logs = run(["docker", "logs", name], check=False)
            raise SmokeTestError(
                "container exited before noVNC became ready:\n"
                f"{logs.stdout}{logs.stderr}"
            )
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{PORT}/", timeout=1
            ) as response:
                body = response.read().decode()
            if response.status == 200:
                return body
        except OSError:
            time.sleep(0.25)
    raise SmokeTestError("noVNC did not become ready within 30 seconds")


def assert_rfb_authentication() -> None:
    try:
        rejected = authenticate_vnc("127.0.0.1", PORT, f"127.0.0.1:{PORT}", b"00000000")
        accepted = authenticate_vnc(
            "127.0.0.1",
            PORT,
            f"127.0.0.1:{PORT}",
            b"A7x!9Qp#",
            capture_framebuffer=True,
            idle_seconds=1,
        )
    except BrowserProtocolError as exc:
        raise SmokeTestError(str(exc)) from exc
    if rejected.accepted:
        raise SmokeTestError("WebSocket VNC accepted an incorrect password")
    if (
        not accepted.accepted
        or not accepted.desktop_name
        or not accepted.framebuffer_sha256
    ):
        raise SmokeTestError("WebSocket VNC did not open the authenticated desktop")


def run_repeated_healthchecks(name: str) -> None:
    for _ in range(8):
        run(["docker", "exec", name, "/opt/browser-console/healthcheck.sh"])


def assert_chromium_policy(name: str, ca_file: Path) -> None:
    policy_text = run(
        [
            "docker",
            "exec",
            name,
            "cat",
            "/etc/chromium/policies/managed/ca-certificates.json",
        ]
    ).stdout
    policy = cast(dict[str, list[str]], json.loads(policy_text))
    expected = subprocess.run(
        ["openssl", "x509", "-in", str(ca_file), "-outform", "DER"],
        capture_output=True,
        check=False,
    )
    if expected.returncode != 0:
        raise SmokeTestError("OpenSSL could not convert the mounted CA to DER")
    expected_der = expected.stdout
    actual_der = base64.b64decode(policy["CACertificates"][0])
    if actual_der != expected_der:
        raise SmokeTestError(
            "Chromium CACertificates policy does not contain the mounted CA"
        )
    probe = ["docker", "exec", name, "/opt/browser-console/policy-probe.py"]
    run(
        [
            *probe,
            "policy",
            "--ca-file",
            "/run/browser-console-ca/ca.crt",
        ]
    )
    run([*probe, "assert-cookie-absent"])
    run([*probe, "set-cookie"])


def assert_image_contract(image: str) -> None:
    raw = run(["docker", "image", "inspect", image]).stdout
    images = cast(list[dict[str, object]], json.loads(raw))
    config = cast(dict[str, object], images[0]["Config"])
    exposed = cast(dict[str, object], config["ExposedPorts"])
    if set(exposed) != {"6080/tcp"}:
        raise SmokeTestError(f"unexpected exposed ports: {sorted(exposed)}")
    if config["User"] != "10001:10001":
        raise SmokeTestError(f"image runs as {config['User']!r}, not UID/GID 10001")


def assert_chromium_running(name: str) -> None:
    processes = run(["docker", "top", name, "-eo", "pid,user,comm,args"]).stdout
    if "/usr/lib/chromium/chromium" not in processes:
        raise SmokeTestError(
            f"Chromium did not remain running with its sandbox enabled:\n{processes}"
        )
    if "--no-sandbox" in processes:
        raise SmokeTestError("Chromium must not run with --no-sandbox")


def assert_chromium_exit_stops_container(name: str) -> None:
    find_pid = """
for command in /proc/[0-9]*/cmdline; do
    process=$(tr '\\0' ' ' < "${command}")
    if [[ ${process} == /usr/lib/chromium/chromium* && ${process} != *" --type="* ]]; then
        basename "$(dirname "${command}")"
        exit 0
    fi
done
exit 1
"""
    chromium_pid = run(["docker", "exec", name, "bash", "-c", find_pid]).stdout.strip()
    run(
        [
            "docker",
            "exec",
            name,
            "bash",
            "-c",
            'kill -TERM "$1"',
            "--",
            chromium_pid,
        ]
    )
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        status = run(
            ["docker", "inspect", "--format", "{{.State.Running}}", name]
        ).stdout.strip()
        if status != "true":
            return
        time.sleep(0.25)
    raise SmokeTestError("container remained running after Chromium exited")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="browser-console:test")
    args = parser.parse_args()
    image = cast(str, args.image)
    name = f"browser-console-smoke-{os.getpid()}"

    assert_image_contract(image)
    with tempfile.TemporaryDirectory(prefix="browser-console-smoke-") as temp_name:
        work = Path(temp_name)
        (work / "password").write_text("A7x!9Qp#")
        (work / "password").chmod(0o444)
        ca_file = work / "ca.crt"
        run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=Browser Console Smoke CA",
                "-keyout",
                str(work / "ca.key"),
                "-out",
                str(ca_file),
            ]
        )
        ca_file.chmod(0o444)
        try:
            run(docker_run_args(name, image, work, include_ca=True))
            page = wait_for_novnc(name)
            if "noVNC" not in page:
                raise SmokeTestError("GET / did not return the noVNC client")
            run_repeated_healthchecks(name)
            assert_rfb_authentication()
            assert_chromium_policy(name, ca_file)
            assert_chromium_running(name)
            run(
                [
                    "docker",
                    "exec",
                    name,
                    "sh",
                    "-c",
                    "test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token",
                ]
            )
            assert_chromium_exit_stops_container(name)
        finally:
            run(["docker", "stop", "--time", "10", name], check=False)
            run(["docker", "rm", name], check=False)

        name = f"browser-console-smoke-no-ca-{os.getpid()}"
        try:
            run(docker_run_args(name, image, work, include_ca=False))
            page = wait_for_novnc(name)
            if "noVNC" not in page:
                raise SmokeTestError(
                    "GET / did not return the noVNC client without a CA"
                )
            assert_chromium_running(name)
            run(["docker", "exec", name, "/opt/browser-console/healthcheck.sh"])
        finally:
            run(["docker", "stop", "--time", "10", name], check=False)
            run(["docker", "rm", name], check=False)

    print("Browser console image smoke test: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
