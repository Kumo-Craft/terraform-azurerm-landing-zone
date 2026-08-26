# TFLint config for the Terraform modules in this repo.
#
# Idiomatic Terraform lint — deprecated syntax, invalid Azure SKUs / resource
# types, unused variables — that security scanners (Checkov / Trivy) do NOT
# cover. Runs in .github/workflows/iac-security.yml.

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# NOTE — do NOT reference a rule that isn't present in the pinned ruleset
# version: tflint aborts with "Rule not found" on EVERY module (fatal, not a
# finding). Add `rule "<name>" { enabled = false }` blocks only for rules that
# actually emit false positives, identified from real run findings. (The old
# `azurerm_resource_group_invalid_name` disable was removed — that rule does not
# exist in ruleset 0.29.0 and was breaking the whole recursive run.)
