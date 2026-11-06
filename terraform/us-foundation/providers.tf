terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "2.12.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"

  features {}
}
