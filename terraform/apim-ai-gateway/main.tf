data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = var.foundation_state_path == null ? abspath("${path.module}/../apim-only/terraform.tfstate") : abspath(var.foundation_state_path)
  }
}

locals {
  foundation      = data.terraform_remote_state.foundation.outputs.gateway_foundation
  ai_gateway_name = var.gateway_name == null ? "aigw-test-${local.foundation.name_suffix}" : var.gateway_name
  ai_gateway_id   = "${local.foundation.resource_group_id}/providers/Microsoft.ApiManagement/service/${local.ai_gateway_name}"
  workspace_id    = "${local.ai_gateway_id}/workspaces/default"
  models          = var.ai_gateway_enabled ? local.foundation.models : {}
  management_api  = "2025-09-01-preview"
  openai_base_url = "https://${local.ai_gateway_name}.azure-api.net/default/models/openai/v1"
}

data "azapi_resource_list" "gateway_subnet_occupants" {
  count = var.ai_gateway_enabled ? 1 : 0

  type                   = "Microsoft.ApiManagement/service@2024-05-01"
  parent_id              = local.foundation.resource_group_id
  response_export_values = ["value"]
}

resource "azapi_resource" "ai_gateway" {
  count = var.ai_gateway_enabled ? 1 : 0

  type      = "Microsoft.ApiManagement/service@${local.management_api}"
  name      = local.ai_gateway_name
  parent_id = local.foundation.resource_group_id
  location  = local.foundation.location
  tags      = local.foundation.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name     = "AIGateway"
      capacity = 1
    }
    properties = {
      publisherEmail      = local.foundation.publisher_email
      publisherName       = local.foundation.publisher_name
      publicNetworkAccess = "Enabled"
      virtualNetworkType  = "External"
      virtualNetworkConfiguration = {
        subnetResourceId = local.foundation.outbound_subnet_id
      }
    }
  }

  schema_validation_enabled = false
  response_export_values = [
    "properties.gatewayUrl",
    "properties.provisioningState",
    "properties.publicNetworkAccess",
    "properties.virtualNetworkConfiguration",
  ]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    precondition {
      condition     = !local.foundation.standard_gateway_enabled
      error_message = "Disable standard_gateway_enabled and apply the apim-only root before provisioning AI Gateway."
    }
    precondition {
      condition = alltrue([
        for gateway in data.azapi_resource_list.gateway_subnet_occupants[0].output.value :
        lower(gateway.name) == lower(local.ai_gateway_name) ||
        try(lower(gateway.properties.virtualNetworkConfiguration.subnetResourceId), null) != lower(local.foundation.outbound_subnet_id)
      ])
      error_message = "Another gateway still occupies the outbound subnet. Remove it through its owning Terraform root before enabling AI Gateway."
    }
  }
}

resource "azurerm_role_assignment" "foundry_user" {
  count = var.ai_gateway_enabled ? 1 : 0

  scope                            = local.foundation.foundry_account_id
  role_definition_id               = "/subscriptions/${local.foundation.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azapi_resource.ai_gateway[0].identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "wait_for_foundry_rbac" {
  count = var.ai_gateway_enabled ? 1 : 0

  create_duration = "60s"
  triggers = {
    role_assignment_id = azurerm_role_assignment.foundry_user[0].id
  }
}

resource "azapi_resource" "foundry_provider" {
  count = var.ai_gateway_enabled ? 1 : 0

  type      = "Microsoft.ApiManagement/service/workspaces/modelProviders@${local.management_api}"
  name      = local.foundation.foundry_name
  parent_id = local.workspace_id
  body = {
    properties = {
      kind        = "Foundry"
      displayName = "Microsoft Foundry"
      description = "Managed-identity connection to the existing private Foundry account."
      foundry = {
        endpoint    = "https://${local.foundation.foundry_name}.services.ai.azure.com"
        resourceIds = [local.foundation.foundry_account_id]
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

  depends_on = [time_sleep.wait_for_foundry_rbac]
}

resource "azapi_resource" "gateway_model" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/service/workspaces/modelProviders/models@${local.management_api}"
  name      = each.value.resource_name
  parent_id = azapi_resource.foundry_provider[0].id
  body = {
    properties = merge(
      {
        displayName        = each.value.deployment_name
        supportedEndpoints = ["/openai/v1/chat/completions"]
        deployment = {
          resourceId   = each.value.deployment_id
          modelName    = each.value.deployment_name
          modelVersion = each.value.version
        }
      },
      each.value.format == "OpenAI" ? { apiFormat = "OpenAIChatCompletions" } : {},
    )
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "model_alias" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/service/workspaces/aliases@${local.management_api}"
  name      = each.value.resource_name
  parent_id = local.workspace_id
  body = {
    properties = {
      aliasName = each.value.deployment_name
      backendModels = [{
        resourceId = azapi_resource.gateway_model[each.key].id
      }]
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "runtime_api_key" {
  count = var.ai_gateway_enabled ? 1 : 0

  type      = "Microsoft.ApiManagement/service/apiKeys@${local.management_api}"
  name      = "test-client"
  parent_id = azapi_resource.ai_gateway[0].id
  body = {
    properties = {
      displayName = "Test environment client"
    }
  }

  schema_validation_enabled = false

  lifecycle {
    # The preview service owns the display label, not the key's name or access.
    ignore_changes = [body.properties.displayName]
  }
}

resource "azapi_resource_action" "runtime_api_key_secrets" {
  count = var.ai_gateway_enabled ? 1 : 0

  type        = "Microsoft.ApiManagement/service/apiKeys@${local.management_api}"
  resource_id = azapi_resource.runtime_api_key[0].id
  action      = "listSecrets"
  method      = "POST"
  body        = {}

  sensitive_response_export_values = ["primaryKey"]
}

resource "azurerm_private_endpoint" "ai_gateway" {
  count = var.ai_gateway_enabled ? 1 : 0

  name                = "pe-aigw-test-inbound-${local.foundation.name_suffix}"
  resource_group_name = local.foundation.resource_group_name
  location            = local.foundation.location
  subnet_id           = local.foundation.inbound_subnet_id
  tags                = local.foundation.tags

  private_service_connection {
    name                           = "ai-gateway-inbound"
    private_connection_resource_id = azapi_resource.ai_gateway[0].id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "ai-gateway"
    private_dns_zone_ids = [local.foundation.private_dns_zone_id]
  }
}
