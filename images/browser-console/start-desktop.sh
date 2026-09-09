#!/usr/bin/env bash
set -Eeuo pipefail

readonly password_file=/run/secrets/vnc/password
readonly runtime_dir=/run/browser-console
readonly password_target=${runtime_dir}/passwd
readonly browser_ca_file=${BROWSER_CA_FILE:-}
readonly policy_dir=/etc/chromium/policies/managed
readonly policy_target=${policy_dir}/ca-certificates.json

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
if [[ -n "${browser_ca_file}" ]]; then
  if [[ ! -s "${browser_ca_file}" ]]; then
    echo "BROWSER_CA_FILE does not point to a readable certificate" >&2
    exit 1
  fi
  if [[ ! -d "${policy_dir}" || ! -w "${policy_dir}" ]]; then
    echo "Chromium policy volume is missing or not writable" >&2
    exit 1
  fi
  if ! certificate="$(openssl x509 \
    -in "${browser_ca_file}" \
    -outform DER | base64 -w0)"; then
    echo "BROWSER_CA_FILE does not contain a valid X.509 certificate" >&2
    exit 1
  fi
  printf '{"CACertificates":["%s"]}\n' "${certificate}" >"${policy_target}"
fi

umask 077
vncpasswd -f <"${password_file}" >"${password_target}"
chmod 0600 "${password_target}"

export DISPLAY=:1
export HOME=/home/browser
export LOGNAME=browser
export USER=browser

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

tigervncserver :1 \
  -geometry 1440x768 \
  -depth 24 \
  -rfbport 5901 \
  -localhost yes \
  -fg \
  -SecurityTypes VncAuth \
  -passwd "${password_target}" \
  -xstartup /opt/browser-console/fluxbox-startup &
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
