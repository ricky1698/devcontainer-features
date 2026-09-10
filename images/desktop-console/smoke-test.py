# /// script
# requires-python = ">=3.11"
# ///
"""Exercise the desktop console image through its network and process boundaries."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import cast

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "browser-console"))

from browser_console_protocol import (
    BrowserProtocolError,
    authenticate_vnc,
)

PORT = 16081
PASSWORD = "A7x!9Qp#"


class SmokeTestError(RuntimeError):
    pass


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(argv, text=True, capture_output=True, check=False)
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise SmokeTestError(f"{argv[0]} failed: {detail}")
    return result


def docker_run_args(
    name: str,
    image: str,
    work: Path,
    *,
    geometry: str | None,
    sandbox: list[str],
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
        *sandbox,
        "--tmpfs",
        "/home/desktop:rw,uid=10001,gid=10001,mode=0750",
        "--tmpfs",
        "/run/desktop-console:rw,uid=10001,gid=10001,mode=0750",
        "--tmpfs",
        "/tmp:rw,uid=10001,gid=10001,mode=1777",
        "--tmpfs",
        "/dev/shm:rw,uid=10001,gid=10001,mode=1777,size=2g",
        "--mount",
        f"type=bind,src={work / 'password'},dst=/run/secrets/vnc/password,readonly",
        "--publish",
        f"127.0.0.1:{PORT}:6080",
    ]
    if geometry is not None:
        arguments.extend(["--env", f"DESKTOP_GEOMETRY={geometry}"])
    arguments.append(image)
    return arguments


# Chrome's sandbox creates PID and network namespaces and then chroots. Docker's
# default seccomp profile only permits that with CAP_SYS_ADMIN and
# CAP_SYS_CHROOT; an unconfined profile (the Kubernetes default) needs no
# capabilities at all.
SECCOMP_UNCONFINED = ["--security-opt", "seccomp=unconfined"]
SECCOMP_DEFAULT_WITH_CAPS = ["--cap-add", "SYS_ADMIN", "--cap-add", "SYS_CHROOT"]
CHROME = [
    "google-chrome",
    "--no-first-run",
    "--no-default-browser-check",
    "--password-store=basic",
    "about:blank",
]


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
            PASSWORD.encode(),
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
        run(["docker", "exec", name, "/opt/desktop-console/healthcheck.sh"])


def assert_traditional_chinese_fonts(name: str) -> None:
    families = run(["docker", "exec", name, "fc-list", ":lang=zh-tw", "family"]).stdout
    if "Noto Sans CJK TC" not in families:
        raise SmokeTestError("Image does not provide a Traditional Chinese font")


def assert_geometry(name: str, expected: str) -> None:
    output = run(["docker", "exec", name, "xdpyinfo", "-display", ":1"]).stdout
    match = re.search(r"dimensions:\s+(\d+x\d+) pixels", output)
    if match is None:
        raise SmokeTestError("xdpyinfo did not report the screen dimensions")
    if match.group(1) != expected:
        raise SmokeTestError(
            f"desktop geometry is {match.group(1)}, expected {expected}"
        )


def assert_window_opens(name: str, command: list[str], window_class: str) -> None:
    run(["docker", "exec", "--detach", name, *command])
    pattern = re.compile(rf'\("{re.escape(window_class)}" "[^"]*"\)\s+(\d+)x(\d+)')
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        tree = run(
            ["docker", "exec", name, "xwininfo", "-display", ":1", "-root", "-tree"],
            check=False,
        ).stdout
        for match in pattern.finditer(tree):
            if int(match.group(1)) >= 400 and int(match.group(2)) >= 400:
                return
        time.sleep(0.5)
    raise SmokeTestError(f"{command[0]} did not open a visible {window_class} window")


def assert_chrome_sandboxed(name: str) -> None:
    processes = run(["docker", "top", name, "-eo", "pid,user,comm,args"]).stdout
    if "/opt/google/chrome/chrome" not in processes:
        raise SmokeTestError(f"Google Chrome is not running:\n{processes}")
    if "--no-sandbox" in processes:
        raise SmokeTestError("Google Chrome must not run with --no-sandbox")


def assert_image_contract(image: str) -> None:
    raw = run(["docker", "image", "inspect", image]).stdout
    images = cast(list[dict[str, object]], json.loads(raw))
    config = cast(dict[str, object], images[0]["Config"])
    exposed = cast(dict[str, object], config["ExposedPorts"])
    if set(exposed) != {"6080/tcp"}:
        raise SmokeTestError(f"unexpected exposed ports: {sorted(exposed)}")
    if config["User"] != "10001:10001":
        raise SmokeTestError(f"image runs as {config['User']!r}, not UID/GID 10001")


def assert_fluxbox_exit_stops_container(name: str) -> None:
    run(["docker", "exec", name, "pkill", "--exact", "--signal", "TERM", "fluxbox"])
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        status = run(
            ["docker", "inspect", "--format", "{{.State.Running}}", name]
        ).stdout.strip()
        if status != "true":
            return
        time.sleep(0.25)
    raise SmokeTestError("container remained running after Fluxbox exited")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="desktop-console:test")
    args = parser.parse_args()
    image = cast(str, args.image)

    assert_image_contract(image)
    with tempfile.TemporaryDirectory(prefix="desktop-console-smoke-") as temp_name:
        work = Path(temp_name)
        (work / "password").write_text(PASSWORD)
        (work / "password").chmod(0o444)

        name = f"desktop-console-smoke-{os.getpid()}"
        try:
            run(
                docker_run_args(
                    name, image, work, geometry=None, sandbox=SECCOMP_UNCONFINED
                )
            )
            page = wait_for_novnc(name)
            if "noVNC" not in page:
                raise SmokeTestError("GET / did not return the noVNC client")
            run_repeated_healthchecks(name)
            assert_traditional_chinese_fonts(name)
            assert_geometry(name, "1920x1080")
            assert_rfb_authentication()
            assert_window_opens(name, ["tilix"], "tilix")
            assert_window_opens(name, CHROME, "google-chrome")
            assert_chrome_sandboxed(name)
            assert_fluxbox_exit_stops_container(name)
        finally:
            run(["docker", "stop", "--time", "10", name], check=False)
            run(["docker", "rm", name], check=False)

        name = f"desktop-console-smoke-geometry-{os.getpid()}"
        try:
            run(
                docker_run_args(
                    name,
                    image,
                    work,
                    geometry="1280x720",
                    sandbox=SECCOMP_DEFAULT_WITH_CAPS,
                )
            )
            wait_for_novnc(name)
            assert_geometry(name, "1280x720")
            run(["docker", "exec", name, "/opt/desktop-console/healthcheck.sh"])
            assert_window_opens(name, CHROME, "google-chrome")
            assert_chrome_sandboxed(name)
        finally:
            run(["docker", "stop", "--time", "10", name], check=False)
            run(["docker", "rm", name], check=False)

    print("Desktop console image smoke test: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
