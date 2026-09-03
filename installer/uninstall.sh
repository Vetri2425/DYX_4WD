#!/usr/bin/env bash
set -euo pipefail

# uninstall.sh
#
# Responsibility: Remove the DYX 4WD production stack, services, and generated runtime state.
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

echo "uninstall.sh: would run in '${MODE}' mode."
echo "uninstall.sh: not implemented."
exit 1
