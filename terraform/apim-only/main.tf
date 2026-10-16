resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  ai_gateway_name            = "aigw-foundry-${random_string.suffix.result}"
  foundry_name               = "fdry-aigw-${random_string.suffix.result}"
  ai_gateway_openai_base_url = "https://${local.ai_gateway_name}.azure-api.net/default/models/openai/v1"
  ai_gateway_workspace_id    = "${azapi_resource.ai_gateway.id}/workspaces/default"

  models = {
    gpt5_4_mini = {
      resource_name   = "gpt5-4mini"
      deployment_name = "Gpt5.4mini"
      format          = "OpenAI"
      catalog_name    = "gpt-5.4-mini"
      version         = "2026-03-17"
      api_format      = "OpenAIChatCompletions"
      sku_name        = "GlobalStandard"
      capacity        = 1
    }
    phi = {
      resource_name   = "phi"
      deployment_name = "Phi"
      format          = "Microsoft"
      catalog_name    = "Phi-4"
      version         = "7"
      api_format      = null
      sku_name        = "GlobalStandard"
      capacity        = 1
    }
    deepseek = {
      resource_name   = "fw-deepseek-v4-1-flash"
      deployment_name = "FW-DeepSeek-V4.1-Flash"
      format          = "DeepSeek"
      catalog_name    = "DeepSeek-V4-Flash"
      version         = "2026-04-23"
      api_format      = null
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
        bypass              = "None"
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

resource "azapi_resource" "ai_gateway" {
  type      = "Microsoft.ApiManagement/service@2025-09-01-preview"
  name      = local.ai_gateway_name
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name     = "AIGateway"
      capacity = 1
    }
    properties = {
      publisherEmail      = var.publisher_email
      publisherName       = var.publisher_name
      publicNetworkAccess = "Enabled"
      virtualNetworkType  = "External"
      virtualNetworkConfiguration = {
        subnetResourceId = azurerm_subnet.ai_gateway_outbound.id
      }
    }
  }

  response_export_values = [
    "properties.gatewayUrl",
    "properties.frontend.defaultHostname",
    "properties.provisioningState",
    "properties.publicNetworkAccess",
    "properties.virtualNetworkType",
    "properties.virtualNetworkConfiguration",
  ]

  schema_validation_enabled = false

  timeouts {
    create = "45m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [
    azurerm_network_security_rule.ai_gateway_outbound,
    azurerm_subnet_network_security_group_association.ai_gateway_outbound,
    azurerm_private_endpoint.foundry,
    azurerm_private_dns_zone_virtual_network_link.foundry,
  ]
}

resource "azurerm_role_assignment" "ai_gateway_foundry_user" {
  scope                            = azapi_resource.foundry.id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azapi_resource.ai_gateway.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "wait_for_foundry_rbac" {
  create_duration = "60s"
  triggers = {
    role_assignment_id = azurerm_role_assignment.ai_gateway_foundry_user.id
  }

  depends_on = [azurerm_role_assignment.ai_gateway_foundry_user]
}

resource "azapi_resource" "foundry_provider" {
  type      = "Microsoft.ApiManagement/service/workspaces/modelProviders@2025-09-01-preview"
  name      = local.foundry_name
  parent_id = local.ai_gateway_workspace_id

  body = {
    properties = {
      kind        = "Foundry"
      displayName = "Microsoft Foundry"
      description = "Managed-identity connection to the Sweden Central Foundry account."
      foundry = {
        endpoint    = "https://${local.foundry_name}.services.ai.azure.com"
        resourceIds = [azapi_resource.foundry.id]
        authentication = {
          kind = "ManagedIdentity"
          managedIdentity = {
            resource = "https://cognitiveservices.azure.com/"
          }
        }
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    time_sleep.wait_for_foundry_rbac,
    azurerm_cognitive_deployment.model,
  ]
}

resource "azapi_resource" "gateway_model" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/service/workspaces/modelProviders/models@2025-09-01-preview"
  name      = each.value.resource_name
  parent_id = azapi_resource.foundry_provider.id

  body = {
    properties = merge(
      {
        displayName        = each.value.deployment_name
        supportedEndpoints = ["/openai/v1/chat/completions"]
        deployment = {
          resourceId   = azurerm_cognitive_deployment.model[each.key].id
          modelName    = each.value.deployment_name
          modelVersion = each.value.version
        }
      },
      each.value.api_format == null ? {} : { apiFormat = each.value.api_format },
    )
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "model_alias" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/service/workspaces/aliases@2025-09-01-preview"
  name      = each.value.resource_name
  parent_id = local.ai_gateway_workspace_id

  body = {
    properties = {
      aliasName = each.value.deployment_name
      backendModels = [
        {
          resourceId = azapi_resource.gateway_model[each.key].id
        }
      ]
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "runtime_api_key" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  name      = each.value.resource_name
  parent_id = azapi_resource.ai_gateway.id

  body = {
    properties = {
      displayName = "${each.value.deployment_name} client"
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource_action" "runtime_api_key_secrets" {
  for_each = local.models

  type        = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  resource_id = azapi_resource.runtime_api_key[each.key].id
  action      = "listSecrets"
  method      = "POST"
  body        = {}

  sensitive_response_export_values = ["primaryKey"]
}
