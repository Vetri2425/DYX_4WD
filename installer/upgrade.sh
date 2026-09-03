#!/usr/bin/env bash
set -euo pipefail

# upgrade.sh
#
# Responsibility: Upgrade the current release: verify, stop services, install, switch symlink, restart, health check (Section 47).
#
# Milestone 1 skeleton -- argument parsing only, no implementation.
# The installer must never report success for work it did not perform.

MODE=""

usage() {
  echo "Usage: $0 [--dev|--production]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      MODE="dev"
      shift
      ;;
    --production)
      MODE="production"
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage
fi

echo "upgrade.sh: would run in '${MODE}' mode."
echo "upgrade.sh: not implemented."
exit 1
