###############################################################
# TERRAFORM BLOCK
# Description: Specifies required Terraform and provider versions
# Terraform version: >= 1.12.0 (aligned with repo standard)
#
# This module wraps Azure/naming/azurerm (v0.4.3) — a name generator,
# not an Azure resource module. It therefore declares no azurerm or
# time provider. The upstream module pulls hashicorp/random itself.
###############################################################
terraform {
  required_version = ">= 1.12.0"
}
