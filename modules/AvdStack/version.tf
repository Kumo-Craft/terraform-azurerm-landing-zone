terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # AvdSessionHost composes time_static for the CreatedOn tag.
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}
