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
    model_router = {
      deployment_name = "model-router"
      format          = "OpenAI"
      catalog_name    = "model-router"
      version         = "2025-11-18"
      sku_name        = "GlobalStandard"
      capacity        = 1000
    }
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
      capacity        = 10
    }
    kimi_k3 = {
      deployment_name = "FW-Kimi-K3"
      format          = "Fireworks"
      catalog_name    = "FW-Kimi-K3"
      version         = "1"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }
    gpt_chat_latest = {
      deployment_name = "gpt-chat-latest"
      format          = "OpenAI"
      catalog_name    = "gpt-chat-latest"
      version         = "2026-10-07"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }
  }

  models = {
    for key, model in local.requested_models : key => model
    if key != "deepseek" || var.enable_deepseek
  }

  azurerm_models = {
    for key, model in local.models : key => model
    if key != "model_router"
  }

  model_router_preserved_properties = try({
    for key, value in data.azapi_resource.model_router_current.output.properties : key => value
    if contains([
      "capacitySettings",
      "currentCapacity",
      "deploymentState",
      "parentDeploymentName",
      "raiPolicyName",
      "serviceTier",
      "spilloverDeploymentName",
    ], key) && value != null
  }, {})

  model_router_preserved_scale_settings = try({
    for key, value in data.azapi_resource.model_router_current.output.properties.scaleSettings : key => value
    if contains(["capacity", "scaleType"], key) && value != null
  }, {})

  model_router_preserved_model = try({
    for key, value in data.azapi_resource.model_router_current.output.properties.model : key => value
    if contains(["publisher", "source", "sourceAccount"], key) && value != null
  }, {})

  model_router_preserved_sku = try({
    for key, value in data.azapi_resource.model_router_current.output.sku : key => value
    if contains(["family", "size", "tier"], key) && value != null
  }, {})

  anthropic_models = {
    claude_opus_5_5 = {
      deployment_name = "claude-opus-5-5"
      format          = "Anthropic"
      catalog_name    = "claude-opus-5-5"
      version         = "2"
      sku_name        = "GlobalStandard"
      capacity        = 10
    }
    claude_opus_5_5_fast = {
      deployment_name = "claude-opus-5-5-fast"
      format          = "Anthropic"
      catalog_name    = "claude-opus-5-5-fast"
      version         = "2"
      sku_name        = "GlobalStandard"
      capacity        = 10
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
  for_each = local.azurerm_models

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

data "azapi_resource" "model_router_current" {
  type                   = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name                   = local.models.model_router.deployment_name
  parent_id              = "${data.azurerm_resource_group.main.id}/providers/Microsoft.CognitiveServices/accounts/${local.foundry_name}"
  ignore_not_found       = true
  response_export_values = ["properties", "sku"]
}

moved {
  from = azurerm_cognitive_deployment.model["model_router"]
  to   = azapi_resource.model_router
}

resource "azapi_resource" "model_router" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview"
  name      = local.models.model_router.deployment_name
  parent_id = azapi_resource.foundry.id
  tags      = data.azapi_resource.model_router_current.tags

  body = {
    sku = merge(local.model_router_preserved_sku, {
      name     = local.models.model_router.sku_name
      capacity = local.models.model_router.capacity
    })
    properties = merge(
      local.model_router_preserved_properties,
      {
        for key, value in { scaleSettings = local.model_router_preserved_scale_settings } : key => value
        if length(value) > 0
      },
      {
        model = merge(local.model_router_preserved_model, {
          format  = local.models.model_router.format
          name    = local.models.model_router.catalog_name
          version = local.models.model_router.version
        })
        versionUpgradeOption = "NoAutoUpgrade"
        routing = {
          mode   = "balanced"
          models = var.model_router_routing_models
        }
      }
    )
  }

  ignore_missing_property = false
  list_unique_id_property = {
    "properties.routing.models" = "name,version"
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
