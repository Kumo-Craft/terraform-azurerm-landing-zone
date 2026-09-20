terraform {
  required_version = ">= 1.12.0"
  required_providers {
    alz = {
      source  = "Azure/alz"
      version = "~> 0.22"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
