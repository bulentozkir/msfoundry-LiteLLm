resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  foundry_name         = "fdry-aigw-${random_string.suffix.result}"
  fireworks_feature_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Features/providers/Microsoft.CognitiveServices/features/Fireworks.EnableDeploy"

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

  additional_models = {
    claude_opus_5_5 = {
      resource_name   = "claude-opus-5-5"
      deployment_name = "claude-opus-5-5"
      format          = "Anthropic"
      catalog_name    = "claude-opus-5-5"
      version         = "2"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }
    gpt6_astra = {
      resource_name   = "gpt-6-astra"
      deployment_name = "gpt-6-astra"
      format          = "OpenAI"
      catalog_name    = "gpt-6-astra"
      version         = "2026-09-03"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }
    glm5_3_flash = {
      resource_name   = "fw-glm-5-3-flash"
      deployment_name = "FW-GLM-5.3-Flash"
      format          = "Fireworks"
      catalog_name    = "FW-GLM-5.3-Flash"
      version         = "1"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }
    kimi_k3 = {
      resource_name   = "fw-kimi-k3"
      deployment_name = "FW-Kimi-K3"
      format          = "Fireworks"
      catalog_name    = "FW-Kimi-K3"
      version         = "1"
      sku_name        = "GlobalStandard"
      capacity        = 10
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

resource "azapi_resource_action" "fireworks_registration" {
  type        = "Microsoft.CognitiveServices/features@2021-07-01"
  resource_id = local.fireworks_feature_id
  action      = "register"
  method      = "POST"
  body        = {}

  response_export_values = ["properties.state"]
}

data "azapi_resource" "fireworks_feature" {
  type                   = "Microsoft.CognitiveServices/features@2021-07-01"
  resource_id            = local.fireworks_feature_id
  response_export_values = ["properties.state"]
}

resource "azurerm_cognitive_deployment" "additional" {
  for_each = {
    for model_id, model in local.additional_models : model_id => model
    if model.format != "Anthropic"
  }

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
      error_message = "Wait for Fireworks.EnableDeploy to become Registered, then retry the plan. Do not deploy Fireworks models while registration is pending."
    }
  }
}

# AzureRM does not expose the required Anthropic Marketplace attestation.
resource "azapi_resource" "claude_opus_5_5" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name      = local.additional_models.claude_opus_5_5.deployment_name
  parent_id = azapi_resource.foundry.id

  body = {
    sku = {
      name     = local.additional_models.claude_opus_5_5.sku_name
      capacity = local.additional_models.claude_opus_5_5.capacity
    }
    properties = {
      model = {
        format  = local.additional_models.claude_opus_5_5.format
        name    = local.additional_models.claude_opus_5_5.catalog_name
        version = local.additional_models.claude_opus_5_5.version
      }
      modelProviderData    = var.claude_provider_data
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }

  schema_validation_enabled = false
  response_export_values    = ["properties.provisioningState"]
}
