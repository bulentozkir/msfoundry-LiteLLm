data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = var.foundation_state_path == null ? abspath("${path.module}\\..\\us-foundation\\terraform.tfstate") : abspath(var.foundation_state_path)
  }
}

locals {
  foundation             = data.terraform_remote_state.foundation.outputs.gateway_foundation
  gateway_name           = var.gateway_name == null ? "aigw-us-${local.foundation.name_suffix}" : var.gateway_name
  gateway_vnet_id        = regex("(?i)^(.+)/subnets/[^/]+$", local.foundation.outbound_subnet_id)[0]
  workspace_id           = "${azapi_resource.gateway.id}/workspaces/default"
  management_api         = "2025-09-01-preview"
  foundry_role_id        = "/subscriptions/${local.foundation.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  excluded_model_pattern = "(?i)(^|[-_ ])(fable|glm|phi)([-_. 0-9]|$)|gpt[a-z0-9._-]*mini"
}

data "azapi_resource" "foundry_account" {
  type        = "Microsoft.CognitiveServices/accounts@2024-10-01"
  resource_id = local.foundation.foundry_account_id

  response_export_values = [
    "location",
    "properties.endpoint",
    "properties.disableLocalAuth",
    "properties.publicNetworkAccess",
  ]
}

data "azapi_resource" "gateway_subnet" {
  type                   = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id            = local.foundation.outbound_subnet_id
  response_export_values = ["properties.delegations"]
}

data "azapi_resource" "gateway_vnet" {
  type                   = "Microsoft.Network/virtualNetworks@2024-05-01"
  resource_id            = local.gateway_vnet_id
  response_export_values = ["location"]
}

resource "azapi_resource" "gateway" {
  type      = "Microsoft.ApiManagement/aigateways@${local.management_api}"
  name      = local.gateway_name
  parent_id = local.foundation.resource_group_id
  location  = local.foundation.location
  tags      = local.foundation.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      publicNetworkAccess = "Enabled"
      backend = {
        subnet = {
          id = local.foundation.outbound_subnet_id
        }
      }
    }
  }

  schema_validation_enabled = false
  replace_triggers_external_values = {
    backend_subnet_id = lower(local.foundation.outbound_subnet_id)
  }
  response_export_values = [
    "sku.name",
    "properties.frontend.defaultHostname",
    "properties.provisioningState",
    "properties.backend.subnet.id",
  ]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = lower(local.foundation.location) == "eastus2"
      error_message = "This root requires the East US 2 foundation."
    }
    precondition {
      condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", local.gateway_name))
      error_message = "The gateway name derived from foundation state is not a valid 3-24 character dedicated gateway name."
    }
    precondition {
      condition = try(
        lower(data.azapi_resource.foundry_account.output.location) == "eastus2" &&
        data.azapi_resource.foundry_account.output.properties.disableLocalAuth == true &&
        lower(data.azapi_resource.foundry_account.output.properties.publicNetworkAccess) == "disabled" &&
        can(regex("^https://[^/]+", data.azapi_resource.foundry_account.output.properties.endpoint)),
        false
      )
      error_message = "The Foundry account must be in East US 2, have an HTTPS endpoint, and have local authentication and public networking disabled."
    }
    precondition {
      condition = try(anytrue([
        for delegation in data.azapi_resource.gateway_subnet.output.properties.delegations :
        lower(delegation.properties.serviceName) == "microsoft.app/environments"
      ]), false)
      error_message = "The foundation's gateway backend subnet must be delegated to Microsoft.App/environments before gateway creation."
    }
    precondition {
      condition     = try(lower(data.azapi_resource.gateway_vnet.output.location) == "eastus2", false)
      error_message = "The backend subnet's virtual network must be in East US 2."
    }
    precondition {
      condition = (
        length(distinct([for model in values(local.models) : model.resource_name])) == length(local.models) &&
        alltrue([for model in values(local.models) : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", model.resource_name))])
      )
      error_message = "Foundation deployment names must normalize to distinct valid 3-63 character gateway model resource names."
    }
    precondition {
      condition = alltrue([
        for model in values(local.models) :
        lower(model.deployment_id) == "${trimsuffix(lower(local.foundation.foundry_account_id), "/")}/deployments/${lower(model.deployment_name)}"
      ])
      error_message = "Every registered deployment must belong to the foundation Foundry account and match its deployment name."
    }
    precondition {
      condition = alltrue([
        for model in values(local.models) :
        !can(regex(local.excluded_model_pattern, "${model.deployment_name} ${try(model.catalog_name, "")}"))
      ])
      error_message = "The foundation includes an excluded Fable, Phi, GPT mini, or GLM model. Remove it from the foundation before registering models."
    }
    precondition {
      condition     = length(setsubtract(toset(keys(var.model_endpoint_overrides)), toset(keys(local.models)))) == 0
      error_message = "Every model_endpoint_overrides key must exist in gateway_foundation.models."
    }
    postcondition {
      condition     = try(self.output.sku.name == "Premium", false)
      error_message = "The dedicated gateway did not report the expected Premium SKU. Inspect the live service contract before proceeding."
    }
  }
}

resource "azurerm_role_assignment" "foundry_user" {
  scope                            = local.foundation.foundry_account_id
  role_definition_id               = local.foundry_role_id
  principal_id                     = azapi_resource.gateway.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "foundry_rbac" {
  create_duration = var.rbac_propagation_delay
  triggers = {
    role_assignment_id = azurerm_role_assignment.foundry_user.id
  }
}

resource "azapi_resource" "foundry_provider" {
  type      = "Microsoft.ApiManagement/aigateways/workspaces/modelProviders@${local.management_api}"
  name      = local.foundation.foundry_name
  parent_id = local.workspace_id

  body = {
    properties = {
      kind        = "Foundry"
      displayName = local.foundation.foundry_name
      foundry = {
        endpoint    = data.azapi_resource.foundry_account.output.properties.endpoint
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
  depends_on                = [time_sleep.foundry_rbac]
}

resource "azapi_resource" "runtime_key" {
  type      = "Microsoft.ApiManagement/aigateways/apiKeys@${local.management_api}"
  name      = var.runtime_key_name
  parent_id = azapi_resource.gateway.id

  body = {
    properties = {
      displayName = var.runtime_key_display_name
    }
  }

  schema_validation_enabled = false
  response_export_values    = []
}
