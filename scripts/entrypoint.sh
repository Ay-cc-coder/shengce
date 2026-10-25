#!/bin/sh
set -eu

mkdir -p /data
if [ "$(id -u)" = "0" ]; then
  chown -R appuser:appuser /data 2>/dev/null || true
  exec gosu appuser "$@"
fi

exec "$@"
