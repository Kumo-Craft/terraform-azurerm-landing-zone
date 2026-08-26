###############################################################
# TERRAFORM BLOCK
# Description: Specifies required Terraform and provider versions
# Terraform version: >= 1.12.0
# AzureRM provider: ~> 4.0
# Time provider: >= 0.9.0 (for time_static resource)
###############################################################
terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}
