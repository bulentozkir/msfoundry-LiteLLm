terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

provider "azapi" {
  subscription_id = local.foundation.subscription_id
  tenant_id       = local.foundation.tenant_id
}

provider "azurerm" {
  subscription_id                 = local.foundation.subscription_id
  tenant_id                       = local.foundation.tenant_id
  resource_provider_registrations = "none"

  features {}
}
