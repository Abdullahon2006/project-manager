#!/usr/bin/env bash
# State & Next Backend Launch Script
# Runs cleanly as regular user without sudo or root permissions.

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "⚡ Starting State & Next Backend Server on http://127.0.0.1:8000..."
exec uv run python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
