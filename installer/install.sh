#!/usr/bin/env bash
set -euo pipefail

# install.sh
#
# Responsibility: Install the DYX 4WD production stack on a fresh or existing machine (Section 39-40).
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

echo "install.sh: would run in '${MODE}' mode."
echo "install.sh: not implemented."
exit 1
