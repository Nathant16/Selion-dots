#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$PROJECT_ROOT/install/install.sh" "$@"

