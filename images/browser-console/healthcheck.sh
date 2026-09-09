#!/usr/bin/env bash
set -Eeuo pipefail

curl --fail --silent --show-error --max-time 2 http://127.0.0.1:6080/ >/dev/null
bash -c 'exec 3<>/dev/tcp/127.0.0.1/5901'
