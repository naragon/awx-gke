#!/usr/bin/env bash
set -euo pipefail

# Re-enable GitHub Actions for a repository.
# Usage:
#   ./scripts/enable-github-actions.sh [owner/repo]
# Example:
#   ./scripts/enable-github-actions.sh naragon/awx-gke

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install GitHub CLI first."
  exit 1
fi

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  # Try infer from local git remote
  if git remote get-url origin >/dev/null 2>&1; then
    URL="$(git remote get-url origin)"
    REPO="$(echo "$URL" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
  else
    echo "Usage: $0 <owner/repo>"
    exit 1
  fi
fi

echo "Enabling GitHub Actions for $REPO ..."
gh api -X PUT "repos/${REPO}/actions/permissions" --input - <<'JSON'
{"enabled":true,"allowed_actions":"all"}
JSON

echo "Done. Current permissions:"
gh api "repos/${REPO}/actions/permissions"
