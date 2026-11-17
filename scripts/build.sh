#!/usr/bin/env bash
# Run all checks and build the site. Usage: ./scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/verify_outputs.py
python3 tests/check_docs.py
mkdocs build --strict
echo "Site built in ./site"
