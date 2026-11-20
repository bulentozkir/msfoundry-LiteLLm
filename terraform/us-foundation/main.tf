data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  foundry_name         = "fdry-aigw-us-${random_string.suffix.result}"
  fireworks_feature_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Features/providers/Microsoft.CognitiveServices/features/Fireworks.EnableDeploy"

  requested_models = {
    deepseek = {
      deployment_name = "FW-DeepSeek-V4.1-Flash"
      format          = "DeepSeek"
      catalog_name    = "DeepSeek-V4-Flash"
      version         = "2026-04-23"
      sku_name        = "GlobalStandard"
      capacity        = 250
    }
    gpt6_astra = {
      deployment_name = "gpt-6-astra"
      format          = "OpenAI"
      catalog_name    = "gpt-6-astra"
      version         = "2026-09-03"
      sku_name        = "GlobalStandard"
      capacity        = 250
    }
    kimi_k3 = {
      deployment_name = "FW-Kimi-K3"
      format          = "Fireworks"
      catalog_name    = "FW-Kimi-K3"
      version         = "1"
      sku_name        = "GlobalStandard"
      capacity        = 500
    }
    kimi_k3_1_pro = {
      deployment_name = "Kimi-K3.1-Pro"
      format          = "MoonshotAI"
      catalog_name    = "Kimi-K3.1-Pro"
      version         = "2026-11-04"
      sku_name        = "GlobalStandard"
      capacity        = 100
    }
  }

  models = {
    for key, model in local.requested_models : key => model
    if key != "deepseek" || var.enable_deepseek
  }

  anthropic_models = {
    claude_opus_5_5 = {
      deployment_name = "claude-opus-5-5"
      format          = "Anthropic"
      catalog_name    = "claude-opus-5-5"
      version         = "2"
      sku_name        = "GlobalStandard"
      capacity        = 40
    }
  }
}

resource "azapi_resource" "foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.foundry_name
  parent_id = data.azurerm_resource_group.main.id
  location  = data.azurerm_resource_group.main.location
  tags      = data.azurerm_resource_group.main.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
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
      networkInjections = [{
        scenario                   = "agent"
        subnetArmId                = azurerm_subnet.foundry_outbound.id
        useMicrosoftManagedNetwork = false
      }]
    }
  }

  schema_validation_enabled = false
  response_export_values    = ["properties.endpoint", "properties.networkInjections", "properties.publicNetworkAccess"]

  lifecycle {
    precondition {
      condition     = lower(data.azurerm_resource_group.main.location) == "eastus2"
      error_message = "The target resource group must be in East US 2."
    }
  }
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = var.project_name
  parent_id = azapi_resource.foundry.id
  location  = data.azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = var.project_name
    }
  }
}

data "azapi_resource" "fireworks_feature" {
  type                   = "Microsoft.CognitiveServices/features@2021-07-01"
  resource_id            = local.fireworks_feature_id
  response_export_values = ["properties.state"]
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

  lifecycle {
    precondition {
      condition     = each.value.format != "Fireworks" || data.azapi_resource.fireworks_feature.output.properties.state == "Registered"
      error_message = "Fireworks.EnableDeploy must be Registered before deploying Fireworks models."
    }
  }
}

resource "azapi_resource" "anthropic" {
  for_each = local.anthropic_models

  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name      = each.value.deployment_name
  parent_id = azapi_resource.foundry.id

  body = {
    sku = {
      name     = each.value.sku_name
      capacity = each.value.capacity
    }
    properties = {
      model = {
        format  = each.value.format
        name    = each.value.catalog_name
        version = each.value.version
      }
      modelProviderData    = var.claude_provider_data
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }

  schema_validation_enabled = false
  response_export_values    = ["properties.provisioningState"]
}
