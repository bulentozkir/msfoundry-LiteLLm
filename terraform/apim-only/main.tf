resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  ai_gateway_name            = "aigw-foundry-${random_string.suffix.result}"
  foundry_name               = "fdry-aigw-${random_string.suffix.result}"
  app_name                   = "foundry-chat3-${random_string.suffix.result}"
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

resource "azurerm_cognitive_account" "foundry" {
  name                          = local.foundry_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = local.foundry_name
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_cognitive_deployment" "model" {
  for_each = local.models

  name                   = each.value.deployment_name
  cognitive_account_id   = azurerm_cognitive_account.foundry.id
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

resource "azurerm_cognitive_deployment" "deepseek_user" {
  for_each = {
    for user_id in range(1, var.deepseek_user_count + 1) :
    "user${user_id}" => "user${user_id}-${local.models.deepseek.deployment_name}"
  }

  name                   = each.value
  cognitive_account_id   = azurerm_cognitive_account.foundry.id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = local.models.deepseek.format
    name    = local.models.deepseek.catalog_name
    version = local.models.deepseek.version
  }

  sku {
    name     = "DataZoneStandard"
    capacity = var.deepseek_user_capacity
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
      publisherEmail = var.publisher_email
      publisherName  = var.publisher_name
    }
  }

  response_export_values = [
    "properties.gatewayUrl",
    "properties.frontend.defaultHostname",
    "properties.provisioningState",
  ]

  schema_validation_enabled = false

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

resource "azurerm_role_assignment" "ai_gateway_foundry_user" {
  scope                            = azurerm_cognitive_account.foundry.id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azapi_resource.ai_gateway.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "wait_for_foundry_rbac" {
  create_duration = "60s"

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
        resourceIds = [azurerm_cognitive_account.foundry.id]
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
      each.key == "deepseek" ? {
        policies = [
          {
            type       = "costLimit"
            id         = "deepseek-monthly-budget"
            amount     = 0.000000001
            period     = "month"
            counterKey = ["identity"]
            scope      = "resource"
            overrides = [
              {
                apiKeyResourceId = azapi_resource.app3_api_key.id
                amount           = var.deepseek_monthly_budget_usd * 0.334
              },
              {
                apiKeyResourceId = azapi_resource.opencode_api_key.id
                amount           = var.deepseek_monthly_budget_usd * 0.333
              },
              {
                apiKeyResourceId = azapi_resource.zed_api_key.id
                amount           = var.deepseek_monthly_budget_usd * 0.333
              },
            ]
          }
        ]
      } : {},
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

resource "azapi_resource" "app3_api_key" {
  type      = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  name      = "app3"
  parent_id = azapi_resource.ai_gateway.id

  body = {
    properties = {
      displayName = "app3"
    }
  }

  schema_validation_enabled = false
  ignore_body_changes       = ["properties.displayName"]
}

resource "azapi_resource_action" "app3_api_key_secrets" {
  type        = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  resource_id = azapi_resource.app3_api_key.id
  action      = "listSecrets"
  method      = "POST"
  body        = {}

  sensitive_response_export_values = ["primaryKey"]
}

resource "azapi_resource" "opencode_api_key" {
  type      = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  name      = "opencode"
  parent_id = azapi_resource.ai_gateway.id

  body = {
    properties = {
      displayName = "OpenCode"
    }
  }

  schema_validation_enabled = false
  ignore_body_changes       = ["properties.displayName"]
}

resource "azapi_resource_action" "opencode_api_key_secrets" {
  type        = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  resource_id = azapi_resource.opencode_api_key.id
  action      = "listSecrets"
  method      = "POST"
  body        = {}

  sensitive_response_export_values = ["primaryKey"]
}

resource "azapi_resource" "zed_api_key" {
  type      = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  name      = "zed"
  parent_id = azapi_resource.ai_gateway.id

  body = {
    properties = {
      displayName = "Zed"
    }
  }

  schema_validation_enabled = false
  ignore_body_changes       = ["properties.displayName"]
}

resource "azapi_resource_action" "zed_api_key_secrets" {
  type        = "Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview"
  resource_id = azapi_resource.zed_api_key.id
  action      = "listSecrets"
  method      = "POST"
  body        = {}

  sensitive_response_export_values = ["primaryKey"]
}

resource "azurerm_service_plan" "app3" {
  name                = "asp-chat3-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

resource "azurerm_linux_web_app" "app3" {
  name                = local.app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.app3.location
  service_plan_id     = azurerm_service_plan.app3.id
  https_only          = true

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = true
  tags                                           = var.tags

  site_config {
    always_on           = true
    minimum_tls_version = "1.2"

    application_stack {
      dotnet_version = "10.0"
    }
  }

  app_settings = {
    "Apim__BaseUrl"       = local.ai_gateway_openai_base_url
    "Apim__GatewayKey"    = azapi_resource_action.app3_api_key_secrets.sensitive_output.primaryKey
    "Apim__Model"         = local.models.gpt5_4_mini.deployment_name
    "Apim__PhiModel"      = local.models.phi.deployment_name
    "Apim__DeepSeekModel" = local.models.deepseek.deployment_name
  }

  depends_on = [azapi_resource.model_alias]
}
