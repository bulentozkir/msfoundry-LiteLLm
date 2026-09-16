terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
  }

  backend "local" {
    path = "../terraform.tfstate"
  }
}

provider "azurerm" {
  subscription_id = "44d3e5d8-23bc-4517-a680-f2d6359dd516"
  features {}
}

resource "azurerm_container_app" "mlflow_gateway" {
  name                         = "ca-litellm"
  resource_group_name          = "rg-litellm-foundry-test"
  container_app_environment_id = "/subscriptions/44d3e5d8-23bc-4517-a680-f2d6359dd516/resourceGroups/rg-litellm-foundry-test/providers/Microsoft.App/managedEnvironments/cae-litellm-ntzf8l"
  revision_mode                = "Single"

  template {
    container {
      name   = "placeholder"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }
}

resource "azurerm_network_security_group" "aca" {
  name                = "vnet-litellm-ntzf8l-snet-aca-nsg-northcentralus"
  location            = "northcentralus"
  resource_group_name = "rg-litellm-foundry-test"
}

resource "azurerm_network_security_group" "appsvc" {
  name                = "vnet-litellm-ntzf8l-snet-appsvc-nsg-northcentralus"
  location            = "northcentralus"
  resource_group_name = "rg-litellm-foundry-test"
}

resource "azurerm_network_security_group" "pe" {
  name                = "vnet-litellm-ntzf8l-snet-pe-nsg-northcentralus"
  location            = "northcentralus"
  resource_group_name = "rg-litellm-foundry-test"
}

resource "azurerm_network_security_group" "postgres" {
  name                = "vnet-litellm-ntzf8l-snet-postgres-nsg-northcentralus"
  location            = "northcentralus"
  resource_group_name = "rg-litellm-foundry-test"
}

resource "azurerm_resource_group" "foundry" {
  name     = "rg-foundry-litellm-test"
  location = "northcentralus"
}

resource "azurerm_cognitive_account" "foundry" {
  name                  = "fdry-litellm-vemyrs"
  location              = azurerm_resource_group.foundry.location
  resource_group_name   = azurerm_resource_group.foundry.name
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = "fdry-litellm-vemyrs"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_account_project" "foundry" {
  name                 = "litellm-demo"
  location             = azurerm_resource_group.foundry.location
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  identity {
    type = "SystemAssigned"
  }
}