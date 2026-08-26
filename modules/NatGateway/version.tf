terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # azapi is required because the hashicorp/azurerm provider does not yet expose
    # the StandardV2 NAT Gateway SKU (which adds zone-redundancy + larger PIP
    # association limits). Module uses azapi against ARM API 2025-03-01.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
