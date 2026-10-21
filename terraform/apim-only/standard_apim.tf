locals {
  apim_identity_name = "apim-foundry-${random_string.suffix.result}"
  apim_name          = var.gateway_name == null ? local.apim_identity_name : var.gateway_name
  standard_models    = var.standard_gateway_enabled ? local.models : {}
  apim_model_base_urls = {
    for model_id, model in local.standard_models :
    model.deployment_name => "https://${local.apim_name}.azure-api.net/${model.resource_name}/openai/v1"
  }
  # AzureRM API IDs include a revision; client scopes and portal metadata use the current API.
  apim_api_ids = {
    for model_id, api in azurerm_api_management_api.model :
    model_id => trimsuffix(api.id, ";rev=${api.revision}")
  }
}

data "azapi_resource_list" "gateway_subnet_occupants" {
  count = var.standard_gateway_enabled ? 1 : 0

  type                   = "Microsoft.ApiManagement/service@2024-05-01"
  parent_id              = azurerm_resource_group.main.id
  response_export_values = ["value"]

  lifecycle {
    postcondition {
      condition = alltrue([
        for gateway in self.output.value :
        lower(gateway.name) == lower(local.apim_name) ||
        try(lower(gateway.properties.virtualNetworkConfiguration.subnetResourceId), null) != lower(azurerm_subnet.ai_gateway_outbound.id)
      ])
      error_message = "Another gateway occupies the outbound subnet. Disable and apply the AI Gateway root before enabling Standard v2."
    }
  }
}

resource "azapi_resource" "apim" {
  count = var.standard_gateway_enabled ? 1 : 0

  type      = "Microsoft.ApiManagement/service@2024-05-01"
  name      = local.apim_name
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name     = "StandardV2"
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
    "properties.provisioningState",
    "properties.publicNetworkAccess",
    "properties.virtualNetworkType",
    "properties.virtualNetworkConfiguration",
  ]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  depends_on = [
    data.azapi_resource_list.gateway_subnet_occupants,
    azurerm_subnet_network_security_group_association.ai_gateway_outbound,
    azurerm_network_security_rule.ai_gateway_outbound,
    azurerm_private_endpoint.foundry,
    azurerm_private_dns_zone_virtual_network_link.foundry,
  ]
}

resource "azurerm_role_assignment" "apim_foundry_user" {
  count = var.standard_gateway_enabled ? 1 : 0

  scope                            = azapi_resource.foundry.id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azapi_resource.apim[0].identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "wait_for_apim_foundry_rbac" {
  count = var.standard_gateway_enabled ? 1 : 0

  create_duration = "60s"
  triggers = {
    role_assignment_id = azurerm_role_assignment.apim_foundry_user[0].id
  }
}

resource "azurerm_api_management_api" "model" {
  for_each = local.standard_models

  name                  = each.value.resource_name
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azapi_resource.apim[0].name
  revision              = "1"
  display_name          = each.value.deployment_name
  path                  = "${each.value.resource_name}/openai/v1"
  protocols             = ["https"]
  subscription_required = true
  service_url           = "https://${local.foundry_name}.services.ai.azure.com/${each.value.format == "OpenAI" ? "openai/v1" : "models"}"

  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi+json"
    content_value = jsonencode({
      openapi = "3.0.1"
      info = {
        title   = each.value.deployment_name
        version = "1.0"
      }
      paths = {
        for operation_id, operation_path in {
          chat-completions            = "/chat/completions"
          deployment-chat-completions = "/deployments/${each.value.deployment_name}/chat/completions"
          } : operation_path => {
          post = {
            operationId = operation_id
            summary     = "Chat with ${each.value.deployment_name}"
            requestBody = {
              required = true
              content = {
                "application/json" = {
                  schema = {
                    "$ref" = "#/components/schemas/ChatCompletionRequest"
                  }
                }
              }
            }
            responses = {
              "200" = {
                description = "Model completion, including streaming when requested."
              }
            }
          }
        }
      }
      components = {
        schemas = {
          ChatCompletionRequest = {
            type                 = "object"
            required             = ["model", "messages"]
            additionalProperties = true
            properties = {
              model = {
                type = "string"
                enum = [each.value.deployment_name]
              }
              messages = {
                type     = "array"
                minItems = 1
                items = {
                  type                 = "object"
                  additionalProperties = true
                }
              }
            }
          }
        }
      }
    })
  }
}

# The portal's AI Models view selects APIs carrying this reserved tag.
resource "azurerm_api_management_tag" "ai_model" {
  count = var.standard_gateway_enabled ? 1 : 0

  api_management_id = azapi_resource.apim[0].id
  name              = "aimodel"
  display_name      = "aimodel"
}

resource "azurerm_api_management_api_tag" "model" {
  for_each = local.standard_models

  api_id = local.apim_api_ids[each.key]
  name   = azurerm_api_management_tag.ai_model[0].name

  depends_on = [azurerm_api_management_api_policy.model]
}

resource "azurerm_api_management_api_policy" "model" {
  for_each = local.standard_models

  api_name            = azurerm_api_management_api.model[each.key].name
  api_management_name = azapi_resource.apim[0].name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = templatefile("${path.module}/templates/model-policy.xml.tftpl", {
    deployment_name = each.value.deployment_name
    backend_name    = azapi_resource.model_backend[each.key].name
    format          = each.value.format
    tenant_id       = var.tenant_id
    entra_client_id = null
    entra_role      = null
  })

  depends_on = [time_sleep.wait_for_apim_foundry_rbac]
}

resource "azurerm_api_management_subscription" "model" {
  for_each = local.standard_models

  subscription_id     = each.value.resource_name
  display_name        = "${each.value.deployment_name} access"
  api_management_name = azapi_resource.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
  api_id              = local.apim_api_ids[each.key]
  state               = "active"
  allow_tracing       = false

  depends_on = [azurerm_api_management_api_policy.model]
}

resource "azurerm_api_management_product" "model" {
  for_each = local.standard_models

  product_id            = each.value.resource_name
  display_name          = each.value.deployment_name
  description           = "Access only to the ${each.value.deployment_name} Foundry deployment through its dedicated API."
  api_management_name   = azapi_resource.apim[0].name
  resource_group_name   = azurerm_resource_group.main.name
  subscription_required = true
  approval_required     = true
  subscriptions_limit   = 1
  published             = true
}

resource "azurerm_api_management_product_api" "model" {
  for_each = local.standard_models

  product_id          = azurerm_api_management_product.model[each.key].product_id
  api_name            = azurerm_api_management_api.model[each.key].name
  api_management_name = azapi_resource.apim[0].name
  resource_group_name = azurerm_resource_group.main.name

  depends_on = [azurerm_api_management_api_policy.model]
}

resource "azurerm_api_management_product_group" "model" {
  for_each = local.standard_models

  product_id          = azurerm_api_management_product.model[each.key].product_id
  group_name          = "developers"
  api_management_name = azapi_resource.apim[0].name
  resource_group_name = azurerm_resource_group.main.name
}

resource "azapi_resource" "model_backend" {
  for_each = local.standard_models

  type      = "Microsoft.ApiManagement/service/backends@2025-09-01-preview"
  name      = each.value.resource_name
  parent_id = azapi_resource.apim[0].id

  body = {
    properties = {
      title       = each.value.deployment_name
      description = "Foundry ${each.value.catalog_name} deployment ${each.value.deployment_name}."
      protocol    = "http"
      url         = azurerm_api_management_api.model[each.key].service_url
      resourceId  = "https://management.azure.com${azapi_resource.foundry.id}"
      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com/"
        }
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [time_sleep.wait_for_apim_foundry_rbac]
}
