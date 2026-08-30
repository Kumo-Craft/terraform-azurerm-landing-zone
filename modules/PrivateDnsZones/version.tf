terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
    # Transitive dependency of the AVM ptn module (its `regions` submodule
    # reads azapi data sources). Declared explicitly so plan-time tests can
    # mock it (the source must resolve to Azure/azapi, not hashicorp/azapi).
    # Same pin as the other AVM-wrapping modules (AlzArchitecture/AlzManagement).
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
  }
}
