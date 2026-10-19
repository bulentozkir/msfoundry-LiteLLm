resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  foundry_name = "fdry-aigw-${random_string.suffix.result}"

  models = {
    gpt5_4_mini = {
      resource_name   = "gpt5-4mini"
      deployment_name = "Gpt5.4mini"
      format          = "OpenAI"
      catalog_name    = "gpt-5.4-mini"
      version         = "2026-03-17"
      sku_name        = "GlobalStandard"
      capacity        = 1
    }
    phi = {
      resource_name   = "phi"
      deployment_name = "Phi"
      format          = "Microsoft"
      catalog_name    = "Phi-4"
      version         = "7"
      sku_name        = "GlobalStandard"
      capacity        = 1
    }
    deepseek = {
      resource_name   = "fw-deepseek-v4-1-flash"
      deployment_name = "FW-DeepSeek-V4.1-Flash"
      format          = "DeepSeek"
      catalog_name    = "DeepSeek-V4-Flash"
      version         = "2026-04-23"
      sku_name        = "GlobalStandard"
      capacity        = 250
    }
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azapi_resource" "foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.foundry_name
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.foundry_name
      disableLocalAuth       = true
      publicNetworkAccess    = "Disabled"
      networkAcls = {
        defaultAction       = "Deny"
        bypass              = "AzureServices"
        ipRules             = []
        virtualNetworkRules = []
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = azurerm_subnet.foundry_outbound.id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  schema_validation_enabled = false
  response_export_values = [
    "properties.endpoint",
    "properties.publicNetworkAccess",
    "properties.networkInjections",
  ]
}

resource "azurerm_cognitive_deployment" "model" {
  for_each = local.models

  name                   = each.value.deployment_name
  cognitive_account_id   = azapi_resource.foundry.id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = each.value.format
    name    = each.value.catalog_name
    version = each.value.version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }
}
