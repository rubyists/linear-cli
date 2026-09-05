#!/usr/bin/env bash
# Runs Hex's dependency security audit from the app Mix project. This is used
# by the pre-push hook as well as the CI quality gate.

set -euo pipefail

repo_top=$(git rev-parse --show-toplevel)
cd "$repo_top/app"
exec mix hex.audit
