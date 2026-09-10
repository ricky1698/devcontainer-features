#!/usr/bin/env bash
set -Eeuo pipefail

readonly password_file=/run/secrets/vnc/password
readonly runtime_dir=/run/desktop-console
readonly password_target=${runtime_dir}/passwd
readonly geometry=${DESKTOP_GEOMETRY:-1920x1080}

if [[ ! -s "${password_file}" ]]; then
  echo "VNC password Secret is missing or empty" >&2
  exit 1
fi

password=$(<"${password_file}")
if [[ ${#password} -ne 8 ]]; then
  echo "VNC password must contain exactly 8 ASCII characters" >&2
  exit 1
fi
if [[ "${password}" == *[![:graph:]]* ]]; then
  echo "VNC password must contain only visible ASCII characters" >&2
  exit 1
fi
if [[ ! -d "${runtime_dir}" || ! -w "${runtime_dir}" ]]; then
  echo "Runtime volume is missing or not writable" >&2
  exit 1
fi
if [[ ! -d /home/desktop || ! -w /home/desktop ]]; then
  echo "Home volume is missing or not writable" >&2
  exit 1
fi
if [[ ! "${geometry}" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "DESKTOP_GEOMETRY must look like WIDTHxHEIGHT" >&2
  exit 1
fi

umask 077
vncpasswd -f <"${password_file}" >"${password_target}"
chmod 0600 "${password_target}"

export DISPLAY=:1
export HOME=/home/desktop
export LANG=C.UTF-8
export LOGNAME=desktop
export SHELL=/bin/bash
export USER=desktop

cleanup() {
  trap - EXIT INT TERM
  if [[ -n "${novnc_pid:-}" ]]; then
    kill "${novnc_pid}" 2>/dev/null || true
  fi
  if [[ -n "${vnc_pid:-}" ]]; then
    kill "${vnc_pid}" 2>/dev/null || true
  fi
  wait "${novnc_pid:-}" "${vnc_pid:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# websockify connects every client from loopback, so TigerVNC cannot blacklist
# one client without locking out every browser session.
tigervncserver :1 \
  -geometry "${geometry}" \
  -depth 24 \
  -rfbport 5901 \
  -localhost yes \
  -fg \
  -SecurityTypes VncAuth \
  -UseBlacklist no \
  -passwd "${password_target}" \
  -xstartup /opt/desktop-console/fluxbox-startup &
vnc_pid=$!

for _ in {1..120}; do
  if bash -c 'exec 3<>/dev/tcp/127.0.0.1/5901' 2>/dev/null; then
    break
  fi
  if ! kill -0 "${vnc_pid}" 2>/dev/null; then
    echo "TigerVNC exited before opening 127.0.0.1:5901" >&2
    exit 1
  fi
  sleep 0.25
done

if ! bash -c 'exec 3<>/dev/tcp/127.0.0.1/5901' 2>/dev/null; then
  echo "TigerVNC did not open 127.0.0.1:5901" >&2
  exit 1
fi

/opt/novnc/utils/novnc_proxy \
  --listen 0.0.0.0:6080 \
  --vnc 127.0.0.1:5901 \
  --heartbeat 30 &
novnc_pid=$!

set +e
wait -n "${vnc_pid}" "${novnc_pid}"
status=$?
set -e
if [[ ${status} -eq 0 ]]; then
  status=1
fi
exit "${status}"
