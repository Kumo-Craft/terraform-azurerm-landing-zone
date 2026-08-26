###############################################################
# MODULE: Naming - Main
# Description: Thin wrapper around Azure/naming/azurerm. Composes
#              the house suffix list and delegates per-type name
#              generation (prefix, length cap, charset) to upstream.
#
# Usage (in another module):
#   module "naming" {
#     source               = "../Naming"
#     subscription_acronym = var.subscription_acronym
#     environment          = var.environment
#     region_code          = var.region_code
#     workload             = var.workload
#   }
#
#   resource "azurerm_key_vault" "this" {
#     name = module.naming.result.key_vault.name
#     # ...
#   }
###############################################################

locals {
  # House convention suffix: {acr}-{env}-{region}-{workload}[+extra]
  # Upstream module joins these with "-" and prepends the type prefix.
  suffix = concat(
    [
      var.subscription_acronym,
      var.environment,
      var.region_code,
      var.workload,
    ],
    var.extra_suffix,
  )

  # Stable seed so unique_length > 0 stays reproducible across applies
  # for the same inputs. Caller may override via unique_seed.
  effective_unique_seed = var.unique_seed != null ? var.unique_seed : join("-", local.suffix)
}

module "this" {
  source  = "Azure/naming/azurerm"
  version = "0.4.3"

  prefix                 = var.prefix
  suffix                 = local.suffix
  unique-length          = var.unique_length
  unique-seed            = local.effective_unique_seed
  unique-include-numbers = var.unique_include_numbers
}
