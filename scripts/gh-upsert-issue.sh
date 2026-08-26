#!/usr/bin/env bash
# Idempotently upsert a GitHub Issue from a workflow.
# GitHub equivalent of the retired scripts/ado-upsert-workitem.sh (Azure
# Boards work items → GitHub Issues after the migration to GitHub).
#
# Creates an issue ONLY if no issue with the same exact title AND the given
# label already exists — so re-running the weekly watchers does not spawn
# duplicates. Existing issues are left as-is.
#
# Dedup is against ALL states (incl. closed): once a finding has been filed,
# never recreate it — lets you close / dismiss an issue without it
# reappearing each weekly scan.
#
# Usage:  gh-upsert-issue.sh "<title>" "<label>" "<body-markdown>"
# Env (auto-provided by GitHub Actions except the token, which the calling
#      step MUST map via `env: GH_TOKEN: ${{ github.token }}` — and the
#      workflow needs `permissions: issues: write`):
#   GH_TOKEN          - token used by the gh CLI
#   GITHUB_REPOSITORY - <owner>/<repo> (predefined in every workflow run)
#
# Advisory by design: never fails the build. Any API error prints a workflow
# warning and the script still exits 0.
set -uo pipefail

title="${1:?title required}"
label="${2:?label required}"
body="${3:-}"

warn() { echo "::warning::gh-upsert: $*"; }

if [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  warn "GH_TOKEN not set — map it via 'env: GH_TOKEN: \${{ github.token }}'. Skipping."
  exit 0
fi
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set — is this a GitHub Actions run?}"

# Ensure the labels exist (idempotent — --force updates in place, never errors
# on an existing label).
gh label create "$label" --repo "$repo" --force >/dev/null 2>&1 || true
gh label create "auto-generated" --repo "$repo" --force >/dev/null 2>&1 || true

# Dedup: exact-title match among ALL issues carrying the label (any state).
existing=$(gh issue list --repo "$repo" --state all --label "$label" --limit 500 --json title 2>/dev/null \
  | jq --arg t "$title" '[.[] | select(.title == $t)] | length' 2>/dev/null || echo "ERR")

if [ "$existing" = "ERR" ] || [ -z "$existing" ]; then
  warn "dedup query failed (perms? token?) — NOT creating '${title}' to stay safe."
  exit 0
fi
if [ "$existing" -gt 0 ]; then
  echo "skip (already filed): ${title}"
  exit 0
fi

if gh issue create --repo "$repo" \
     --title "$title" \
     --label "$label" --label "auto-generated" \
     --body "$body" >/dev/null 2>&1; then
  echo "created: ${title}"
else
  warn "create failed for '${title}' (does the workflow grant 'issues: write'?)."
fi
exit 0
