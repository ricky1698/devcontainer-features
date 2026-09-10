"""Minimal WebSocket and RFB client used by browser console probes."""

from __future__ import annotations

import base64
import hashlib
import os
import socket
import ssl
import subprocess
import time
from dataclasses import dataclass
from typing import Protocol

WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class BrowserProtocolError(RuntimeError):
    pass


class SocketLike(Protocol):
    def recv(self, size: int, /) -> bytes: ...

    def sendall(self, data: bytes, /) -> None: ...

    def close(self) -> None: ...


class WebSocketStream:
    def __init__(self, connection: SocketLike, initial: bytes = b"") -> None:
        self.connection = connection
        self.raw_buffer = bytearray(initial)
        self.payload_buffer = bytearray()

    def _read_raw(self, size: int) -> bytes:
        while len(self.raw_buffer) < size:
            chunk = self.connection.recv(max(4096, size - len(self.raw_buffer)))
            if not chunk:
                raise BrowserProtocolError("WebSocket closed unexpectedly")
            self.raw_buffer.extend(chunk)
        result = bytes(self.raw_buffer[:size])
        del self.raw_buffer[:size]
        return result

    def _read_frame(self) -> tuple[int, bytes]:
        header = self._read_raw(2)
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            length = int.from_bytes(self._read_raw(2))
        elif length == 127:
            length = int.from_bytes(self._read_raw(8))
        mask = self._read_raw(4) if masked else b""
        payload = self._read_raw(length)
        if mask:
            payload = bytes(
                value ^ mask[index % 4] for index, value in enumerate(payload)
            )
        return opcode, payload

    def _write_frame(self, opcode: int, payload: bytes) -> None:
        mask = os.urandom(4)
        length = len(payload)
        if length < 126:
            header = bytes((0x80 | opcode, 0x80 | length))
        elif length <= 0xFFFF:
            header = bytes((0x80 | opcode, 0x80 | 126)) + length.to_bytes(2)
        else:
            header = bytes((0x80 | opcode, 0x80 | 127)) + length.to_bytes(8)
        masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        self.connection.sendall(header + mask + masked)

    def read_exact(self, size: int) -> bytes:
        while len(self.payload_buffer) < size:
            opcode, payload = self._read_frame()
            if opcode in (0x0, 0x1, 0x2):
                self.payload_buffer.extend(payload)
            elif opcode == 0x8:
                raise BrowserProtocolError("WebSocket peer closed the connection")
            elif opcode == 0x9:
                self._write_frame(0xA, payload)
            elif opcode != 0xA:
                raise BrowserProtocolError(f"Unsupported WebSocket opcode {opcode}")
        result = bytes(self.payload_buffer[:size])
        del self.payload_buffer[:size]
        return result

    def read_message(self) -> tuple[int, bytes]:
        while True:
            opcode, payload = self._read_frame()
            if opcode in (0x1, 0x2):
                return opcode, payload
            if opcode == 0x8:
                raise BrowserProtocolError("WebSocket peer closed the connection")
            if opcode == 0x9:
                self._write_frame(0xA, payload)
            elif opcode != 0xA:
                raise BrowserProtocolError(f"Unsupported WebSocket opcode {opcode}")

    def write(self, payload: bytes) -> None:
        self._write_frame(0x2, payload)

    def write_text(self, payload: str) -> None:
        self._write_frame(0x1, payload.encode())

    def close(self) -> None:
        self.connection.close()


def _read_http_headers(connection: SocketLike) -> tuple[bytes, bytes]:
    response = bytearray()
    while b"\r\n\r\n" not in response:
        chunk = connection.recv(4096)
        if not chunk:
            raise BrowserProtocolError("WebSocket handshake closed unexpectedly")
        response.extend(chunk)
        if len(response) > 65536:
            raise BrowserProtocolError("WebSocket handshake headers are too large")
    headers, initial = bytes(response).split(b"\r\n\r\n", 1)
    return headers, initial


def open_websocket(
    address: str,
    port: int,
    host_header: str,
    *,
    path: str = "/websockify",
    tls_context: ssl.SSLContext | None = None,
    server_hostname: str | None = None,
    subprotocol: str | None = "binary",
) -> WebSocketStream:
    raw = socket.create_connection((address, port), timeout=10)
    connection: SocketLike = raw
    if tls_context is not None:
        connection = tls_context.wrap_socket(raw, server_hostname=server_hostname)
    key = base64.b64encode(os.urandom(16)).decode()
    subprotocol_header = (
        f"Sec-WebSocket-Protocol: {subprotocol}\r\n" if subprotocol else ""
    )
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host_header}\r\n"
        "Connection: Upgrade\r\n"
        "Upgrade: websocket\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"{subprotocol_header}\r\n"
    ).encode()
    connection.sendall(request)
    headers, initial = _read_http_headers(connection)
    lines = headers.decode("iso-8859-1").split("\r\n")
    if " 101 " not in lines[0]:
        connection.close()
        raise BrowserProtocolError(f"WebSocket upgrade failed: {lines[0]}")
    response_headers = {
        name.lower(): value.strip()
        for name, value in (line.split(":", 1) for line in lines[1:] if ":" in line)
    }
    expected_accept = base64.b64encode(
        hashlib.sha1(f"{key}{WEBSOCKET_GUID}".encode(), usedforsecurity=False).digest()
    ).decode()
    if response_headers.get("sec-websocket-accept") != expected_accept:
        connection.close()
        raise BrowserProtocolError("WebSocket server returned an invalid accept key")
    if subprotocol and response_headers.get("sec-websocket-protocol") != subprotocol:
        connection.close()
        raise BrowserProtocolError("WebSocket server did not select binary framing")
    return WebSocketStream(connection, initial)


def _vnc_des_response(password: bytes, challenge: bytes) -> bytes:
    def reverse_bits(value: int) -> int:
        return int(f"{value:08b}"[::-1], 2)

    key = bytes(reverse_bits(value) for value in password.ljust(8, b"\0")[:8])
    result = subprocess.run(
        [
            "openssl",
            "enc",
            "-des-ecb",
            "-provider",
            "legacy",
            "-nopad",
            "-K",
            key.hex(),
        ],
        input=challenge,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise BrowserProtocolError(
            f"OpenSSL could not calculate the VNC response: {result.stderr.decode().strip()}"
        )
    return result.stdout


@dataclass(frozen=True)
class VncAuthentication:
    accepted: bool
    desktop_name: str | None
    framebuffer_sha256: str | None


def _send_key(stream: WebSocketStream, keysym: int, pressed: bool) -> None:
    stream.write(bytes((4, int(pressed), 0, 0)) + keysym.to_bytes(4, byteorder="big"))


def _type_url(stream: WebSocketStream, url: str) -> None:
    control_left = 0xFFE3
    enter = 0xFF0D
    _send_key(stream, control_left, True)
    _send_key(stream, ord("l"), True)
    _send_key(stream, ord("l"), False)
    _send_key(stream, control_left, False)
    time.sleep(0.2)
    for character in url:
        _send_key(stream, ord(character), True)
        _send_key(stream, ord(character), False)
        time.sleep(0.02)
    time.sleep(0.2)
    _send_key(stream, enter, True)
    _send_key(stream, enter, False)


def _framebuffer_digest(
    stream: WebSocketStream, width: int, height: int, bits_per_pixel: int
) -> str:
    if bits_per_pixel % 8 != 0:
        raise BrowserProtocolError(f"Unsupported RFB pixel width {bits_per_pixel}")
    capture_width = min(640, width)
    capture_height = min(360, height)
    capture_x = (width - capture_width) // 2
    capture_y = (height - capture_height) // 2
    stream.write(bytes((2, 0, 0, 1)) + (0).to_bytes(4, signed=True))
    stream.write(
        bytes((3, 0))
        + capture_x.to_bytes(2)
        + capture_y.to_bytes(2)
        + capture_width.to_bytes(2)
        + capture_height.to_bytes(2)
    )
    pixels = bytearray()
    while not pixels:
        message_type = stream.read_exact(1)[0]
        if message_type == 0:
            stream.read_exact(1)
            rectangle_count = int.from_bytes(stream.read_exact(2))
            for _ in range(rectangle_count):
                rectangle = stream.read_exact(12)
                rectangle_width = int.from_bytes(rectangle[4:6])
                rectangle_height = int.from_bytes(rectangle[6:8])
                encoding = int.from_bytes(rectangle[8:12], signed=True)
                if encoding != 0:
                    raise BrowserProtocolError(
                        f"VNC server returned unexpected encoding {encoding}"
                    )
                pixels.extend(
                    stream.read_exact(
                        rectangle_width * rectangle_height * (bits_per_pixel // 8)
                    )
                )
        elif message_type == 1:
            colour_map = stream.read_exact(5)
            colour_count = int.from_bytes(colour_map[3:5])
            stream.read_exact(colour_count * 6)
        elif message_type == 2:
            continue
        elif message_type == 3:
            cut_text = stream.read_exact(7)
            stream.read_exact(int.from_bytes(cut_text[3:7]))
        else:
            raise BrowserProtocolError(f"Unexpected RFB server message {message_type}")
    if len(set(pixels)) < 2:
        raise BrowserProtocolError("VNC framebuffer contains no visible variation")
    return hashlib.sha256(pixels).hexdigest()


def authenticate_vnc(
    address: str,
    port: int,
    host_header: str,
    password: bytes,
    *,
    tls_context: ssl.SSLContext | None = None,
    server_hostname: str | None = None,
    capture_framebuffer: bool = False,
    idle_seconds: float = 0,
    navigate_to: str | None = None,
    navigation_wait_seconds: float = 3,
    websocket_path: str = "/websockify",
) -> VncAuthentication:
    stream = open_websocket(
        address,
        port,
        host_header,
        path=websocket_path,
        tls_context=tls_context,
        server_hostname=server_hostname,
    )
    try:
        version = stream.read_exact(12)
        if not version.startswith(b"RFB 003."):
            raise BrowserProtocolError(f"Unexpected RFB version {version!r}")
        stream.write(version)
        security_count = stream.read_exact(1)[0]
        if security_count == 0:
            raise BrowserProtocolError("VNC server offered no authentication methods")
        security_types = stream.read_exact(security_count)
        if 1 in security_types:
            raise BrowserProtocolError("VNC server permits unauthenticated access")
        if 2 not in security_types:
            raise BrowserProtocolError(
                "VNC server did not offer password authentication"
            )
        stream.write(b"\x02")
        challenge = stream.read_exact(16)
        stream.write(_vnc_des_response(password, challenge))
        accepted = int.from_bytes(stream.read_exact(4)) == 0
        if not accepted:
            return VncAuthentication(False, None, None)

        if idle_seconds > 0:
            time.sleep(idle_seconds)
        stream.write(b"\x01")
        server_init = stream.read_exact(24)
        width = int.from_bytes(server_init[0:2])
        height = int.from_bytes(server_init[2:4])
        if width == 0 or height == 0:
            raise BrowserProtocolError(
                "VNC server returned an invalid framebuffer size"
            )
        name_length = int.from_bytes(server_init[20:24])
        desktop_name = stream.read_exact(name_length).decode("utf-8", errors="replace")
        if navigate_to is not None:
            _type_url(stream, navigate_to)
            time.sleep(navigation_wait_seconds)
        framebuffer_sha256 = (
            _framebuffer_digest(stream, width, height, server_init[4])
            if capture_framebuffer
            else None
        )
        return VncAuthentication(True, desktop_name, framebuffer_sha256)
    finally:
        stream.close()
