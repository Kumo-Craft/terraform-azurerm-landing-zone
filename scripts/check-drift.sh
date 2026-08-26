#!/usr/bin/env bash
# scripts/check-drift.sh
#
# Compares duplicated resource blocks across the orchestrator modules
# (KeyVaultStack, NetworkStack, PaloCluster) against
# their canonical counterparts (KeyVault, ResourceGroup, …) and warns
# if the inline copies have drifted.
#
# This is the CI realisation of the "option (c) accept duplication +
# lint" composition strategy decided in REVIEW/SPRINT-7-AUDIT.md
# (Sprint 7 #1).
#
# Usage:
#   bash scripts/check-drift.sh [--strict]
#
# By default the script outputs warnings and returns 0 (advisory).
# With --strict it returns non-zero on any drift (blocks the CI job).

set -uo pipefail

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

DRIFT_COUNT=0

# --- Helper: extract a `resource "TYPE" "NAME" {` block from a file ---
#
# Outputs the body of the first matching block, with a normalised form
# (whitespace collapsed) so cosmetic differences don't trigger drift.
extract_block() {
  local file="$1" type="$2" name="$3"
  awk -v type="$type" -v name="$name" '
    BEGIN { in_block=0; depth=0 }
    $0 ~ "^resource \"" type "\" \"" name "\"" {
      in_block=1; depth=0; next
    }
    in_block {
      # Count braces to find the closing of the block.
      n = gsub(/\{/, "&"); depth += n
      n = gsub(/\}/, "&"); depth -= n
      print
      if (depth <= 0 && /^}/) { exit }
    }
  ' "$file" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | grep -v '^$'
}

# --- Helper: emit a drift warning ---
warn() {
  echo "::warning file=$2::DRIFT: $1" >&2
  echo "  → $1 ($2 differs from canonical)" >&2
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

# --- Helper: compare a resource block between two files ---
compare_block() {
  local label="$1" canonical="$2" stack="$3" type="$4" name="$5"
  local diff_out

  diff_out=$(diff \
    <(extract_block "$canonical" "$type" "$name") \
    <(extract_block "$stack" "$type" "$name") || true)

  if [[ -n "$diff_out" ]]; then
    warn "$label" "$stack"
    echo "$diff_out" | head -30 >&2
    echo "" >&2
  fi
}

echo "::group::Drift check — orchestrator inline blocks vs canonical modules"

# Paths updated for the AVM-style restructure (v0.1.0) — all leaf and
# stack modules now live under modules/<Name>/.

# --- KeyVault canonical vs KeyVaultStack inline ---
compare_block \
  "modules/KeyVaultStack/main.tf inline azurerm_key_vault.this drifted from modules/KeyVault/main.tf" \
  "modules/KeyVault/main.tf" "modules/KeyVaultStack/main.tf" "azurerm_key_vault" "this"

# --- ResourceGroup canonical vs orchestrators that inline RG creation ---
for stack in KeyVaultStack NetworkStack; do
  if [[ -f "modules/$stack/main.tf" ]]; then
    compare_block \
      "modules/$stack/main.tf inline azurerm_resource_group.this drifted from modules/ResourceGroup/main.tf" \
      "modules/ResourceGroup/main.tf" "modules/$stack/main.tf" "azurerm_resource_group" "this"
  fi
done

# --- PrivateEndpoint canonical vs KeyVaultStack inline ---
compare_block \
  "modules/KeyVaultStack/main.tf inline azurerm_private_endpoint.this drifted from modules/PrivateEndpoint/main.tf" \
  "modules/PrivateEndpoint/main.tf" "modules/KeyVaultStack/main.tf" "azurerm_private_endpoint" "this"

# --- KeyVault canonical vs PaloCluster inline (diskencryption.tf) ---
if [[ -f "modules/PaloCluster/diskencryption.tf" ]]; then
  compare_block \
    "modules/PaloCluster/diskencryption.tf inline azurerm_key_vault.this drifted from modules/KeyVault/main.tf" \
    "modules/KeyVault/main.tf" "modules/PaloCluster/diskencryption.tf" "azurerm_key_vault" "this"
fi

echo "::endgroup::"
echo ""

if [[ $DRIFT_COUNT -eq 0 ]]; then
  echo "✅ No drift detected — all inline blocks match their canonical counterparts."
  exit 0
fi

echo "⚠️  $DRIFT_COUNT drift(s) detected. Review and either:"
echo "    1. Propagate the canonical update to the inline copy in the orchestrator, OR"
echo "    2. Document the intentional divergence in the orchestrator's main.tf with a comment."

if [[ $STRICT -eq 1 ]]; then
  echo "Strict mode → failing the build."
  exit 1
fi
exit 0
