# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright==1.55.0"]
# ///
"""Exercise clipboard sync between real browsers and the desktop through noVNC.

Install the browsers once with:
  uv run --with playwright==1.55.0 playwright install --with-deps chromium firefox
"""

from __future__ import annotations

import argparse
import os
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import cast

from playwright.sync_api import Browser, Error, Page, Playwright, sync_playwright

PORT = 16082
PASSWORD = "A7x!9Qp#"
ORIGIN = f"http://127.0.0.1:{PORT}"
ENGINES = ("chromium", "firefox")


class ClipboardTestError(RuntimeError):
    pass


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(argv, text=True, capture_output=True, check=False)
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ClipboardTestError(f"{argv[0]} failed: {detail}")
    return result


@contextmanager
def desktop(image: str) -> Iterator[str]:
    with tempfile.TemporaryDirectory(prefix="desktop-console-clipboard-") as temp_name:
        password = Path(temp_name) / "password"
        password.write_text(PASSWORD)
        password.chmod(0o444)
        name = f"desktop-console-clipboard-{os.getpid()}"
        run(
            [
                "docker",
                "run",
                "--detach",
                "--name",
                name,
                "--read-only",
                "--cap-drop",
                "ALL",
                "--security-opt",
                "seccomp=unconfined",
                "--tmpfs",
                "/home/desktop:rw,uid=10001,gid=10001,mode=0750",
                "--tmpfs",
                "/run/desktop-console:rw,uid=10001,gid=10001,mode=0750",
                "--tmpfs",
                "/tmp:rw,uid=10001,gid=10001,mode=1777",
                "--tmpfs",
                "/dev/shm:rw,uid=10001,gid=10001,mode=1777,size=2g",
                "--mount",
                f"type=bind,src={password},dst=/run/secrets/vnc/password,readonly",
                "--publish",
                f"127.0.0.1:{PORT}:6080",
                "--env",
                "DESKTOP_GEOMETRY=1280x720",
                image,
            ]
        )
        try:
            yield name
        finally:
            run(["docker", "rm", "--force", name], check=False)


def wait_for_novnc() -> None:
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{ORIGIN}/", timeout=1) as response:
                if 'src="app/clipboard-sync.js"' not in response.read().decode():
                    raise ClipboardTestError("noVNC page does not load clipboard-sync.js")
                return
        except OSError:
            time.sleep(0.25)
    raise ClipboardTestError("noVNC did not become ready within 30 seconds")


def open_mousepad(name: str) -> None:
    run(["docker", "exec", "--detach", name, "mousepad"])
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        tree = run(
            ["docker", "exec", name, "xwininfo", "-display", ":1", "-root", "-tree"],
            check=False,
        ).stdout
        if '("mousepad" "Mousepad")' in tree:
            time.sleep(1)
            return
        time.sleep(0.5)
    raise ClipboardTestError("Mousepad did not open a window")


def launch(playwright: Playwright, engine: str) -> tuple[Browser, Page]:
    if engine == "chromium":
        browser = playwright.chromium.launch()
        context = browser.new_context(viewport={"width": 1280, "height": 720})
        context.grant_permissions(["clipboard-read", "clipboard-write"], origin=ORIGIN)
    else:
        # Firefox has no clipboard permission grant; these prefs let the test
        # set and read the local clipboard without a user gesture.
        browser = playwright.firefox.launch(
            firefox_user_prefs={
                "dom.events.testing.asyncClipboard": True,
                "dom.events.asyncClipboard.readText": True,
            }
        )
        context = browser.new_context(viewport={"width": 1280, "height": 720})
    return browser, context.new_page()


def connect(page: Page) -> None:
    page.goto(f"{ORIGIN}/?password={urllib.parse.quote(PASSWORD)}")
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if page.evaluate("async () => (await import('./app/ui.js')).default.connected"):
            break
        time.sleep(0.25)
    else:
        raise ClipboardTestError("noVNC did not connect")
    # Mousepad opens in the top-left quarter of the desktop.
    box = page.locator("#noVNC_container canvas").bounding_box()
    if box is None:
        raise ClipboardTestError("noVNC canvas is not visible")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        page.mouse.click(box["x"] + box["width"] * 0.15, box["y"] + box["height"] * 0.3)
        if page.evaluate("() => document.activeElement?.tagName === 'CANVAS'"):
            time.sleep(0.5)
            return
        time.sleep(0.5)
    raise ClipboardTestError("noVNC canvas did not take keyboard focus")


def set_local(page: Page, text: str) -> None:
    page.evaluate("text => navigator.clipboard.writeText(text)", text)


def local(page: Page) -> str:
    return cast(str, page.evaluate("() => navigator.clipboard.readText()"))


def expect_local(page: Page, expected: str, label: str) -> None:
    deadline = time.monotonic() + 5
    while True:
        # Firefox in CI has rejected a read right after the copy shortcut,
        # while the ClipboardItem write may still be pending, so retry it.
        try:
            actual = local(page)
        except Error as exc:
            actual = f"<read failed: {exc.message}>"
        if actual == expected or time.monotonic() >= deadline:
            break
        time.sleep(0.2)
    if actual != expected:
        raise ClipboardTestError(f"{label}: local clipboard is {actual!r}, expected {expected!r}")


def copy_document(page: Page) -> None:
    set_local(page, "sentinel")
    page.keyboard.press("Control+a")
    page.keyboard.press("Control+c")


def assert_paste_and_copy(page: Page, engine: str) -> None:
    page.keyboard.type("text to replace")
    for text in (f"{engine} paste 中文 ✓", f"{engine} second paste"):
        set_local(page, text)
        page.keyboard.press("Control+a")
        page.keyboard.press("Control+v")
        time.sleep(0.5)
        # Copying the document back proves Mousepad replaced its selection
        # with the new local text rather than its previous clipboard.
        copy_document(page)
        expect_local(page, text, f"{engine} paste then copy")


def assert_copy_without_remote_change(page: Page, engine: str) -> None:
    set_local(page, "unchanged")
    page.keyboard.press("End")
    page.keyboard.press("Control+c")
    page.keyboard.press("Shift+Home")
    time.sleep(2.5)
    actual = local(page)
    if actual != "unchanged":
        raise ClipboardTestError(
            f"{engine}: copy with nothing selected replaced the local clipboard with {actual!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="desktop-console:test")
    args = parser.parse_args()

    with desktop(cast(str, args.image)) as name:
        wait_for_novnc()
        open_mousepad(name)
        with sync_playwright() as playwright:
            for engine in ENGINES:
                browser, page = launch(playwright, engine)
                try:
                    connect(page)
                    assert_paste_and_copy(page, engine)
                    assert_copy_without_remote_change(page, engine)
                finally:
                    browser.close()
                print(f"{engine}: clipboard sync passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
