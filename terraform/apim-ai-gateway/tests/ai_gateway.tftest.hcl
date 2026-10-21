variables {
  ai_gateway_enabled = true
}

mock_provider "azurerm" {}
mock_provider "time" {}

mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = { value = [] }
    }
  }
}

override_data {
  target = data.terraform_remote_state.foundation
  values = {
    outputs = {
      gateway_foundation = {
        subscription_id          = "00000000-0000-0000-0000-000000000000"
        tenant_id                = "11111111-1111-4111-8111-111111111111"
        resource_group_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        resource_group_name      = "rg-test"
        location                 = "swedencentral"
        tags                     = { environment = "test" }
        name_suffix              = "test01"
        publisher_name           = "Test Team"
        publisher_email          = "admin@example.com"
        standard_gateway_enabled = false
        foundry_account_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
        foundry_name             = "fdry-test01"
        outbound_subnet_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-aigw-outbound"
        inbound_subnet_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-aigw-inbound"
        private_dns_zone_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
        models = {
          gpt5_4_mini = {
            resource_name   = "gpt5-4mini"
            deployment_name = "Gpt5.4mini"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/Gpt5.4mini"
            format          = "OpenAI"
            version         = "2026-03-17"
          }
          phi = {
            resource_name   = "phi"
            deployment_name = "Phi"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/Phi"
            format          = "Microsoft"
            version         = "7"
          }
          deepseek = {
            resource_name   = "fw-deepseek-v4-1-flash"
            deployment_name = "FW-DeepSeek-V4.1-Flash"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/FW-DeepSeek-V4.1-Flash"
            format          = "DeepSeek"
            version         = "2026-04-23"
          }
        }
      }
    }
  }
}

run "private_foundry_ai_gateway" {
  command = plan

  assert {
    condition = (
      azapi_resource.ai_gateway[0].body.sku.name == "AIGateway" &&
      azapi_resource.ai_gateway[0].body.sku.capacity == 1 &&
      azapi_resource.ai_gateway[0].identity[0].type == "SystemAssigned" &&
      azapi_resource.ai_gateway[0].body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.ai_gateway[0].body.properties.virtualNetworkType == "External" &&
      azapi_resource.ai_gateway[0].body.properties.virtualNetworkConfiguration.subnetResourceId == local.foundation.outbound_subnet_id &&
      azapi_resource.ai_gateway[0].type == "Microsoft.ApiManagement/service@2025-09-01-preview"
    )
    error_message = "Use the advertised AIGateway pricing tier with public ingress, managed identity, and the existing outbound subnet."
  }

  assert {
    condition = (
      azapi_resource.foundry_provider[0].body.properties.foundry.resourceIds == [local.foundation.foundry_account_id] &&
      azapi_resource.foundry_provider[0].body.properties.foundry.authentication.kind == "ManagedIdentity" &&
      azapi_resource.foundry_provider[0].body.properties.foundry.authentication.managedIdentity.resource == "https://cognitiveservices.azure.com/" &&
      azurerm_role_assignment.foundry_user[0].scope == local.foundation.foundry_account_id &&
      endswith(azurerm_role_assignment.foundry_user[0].role_definition_id, "/53ca6127-db72-4b80-b1b0-d745d6d5456d")
    )
    error_message = "Reuse the private Foundry account with account-scoped Foundry User and managed identity, never provider keys."
  }

  assert {
    condition = (
      length(azapi_resource.gateway_model) == 3 &&
      length(azapi_resource.model_alias) == 3 &&
      toset(output.model_deployments) == toset(["Gpt5.4mini", "Phi", "FW-DeepSeek-V4.1-Flash"]) &&
      alltrue([
        for model_id, model in local.models :
        azapi_resource.gateway_model[model_id].body.properties.deployment.resourceId == model.deployment_id &&
        azapi_resource.gateway_model[model_id].body.properties.deployment.modelVersion == model.version &&
        azapi_resource.model_alias[model_id].body.properties.aliasName == model.deployment_name
      ]) &&
      azapi_resource.gateway_model["gpt5_4_mini"].body.properties.apiFormat == "OpenAIChatCompletions" &&
      !can(azapi_resource.gateway_model["phi"].body.properties.apiFormat) &&
      !can(azapi_resource.gateway_model["deepseek"].body.properties.apiFormat)
    )
    error_message = "Register exactly the existing three deployments, preserving aliases, versions, and provider-specific API formats."
  }

  assert {
    condition = (
      azurerm_private_endpoint.ai_gateway[0].subnet_id == local.foundation.inbound_subnet_id &&
      contains(azurerm_private_endpoint.ai_gateway[0].private_service_connection[0].subresource_names, "Gateway") &&
      length(azurerm_private_endpoint.ai_gateway[0].private_dns_zone_group[0].private_dns_zone_ids) == 1 &&
      contains(azurerm_private_endpoint.ai_gateway[0].private_dns_zone_group[0].private_dns_zone_ids, local.foundation.private_dns_zone_id) &&
      output.openai_base_url == "https://aigw-test-test01.azure-api.net/default/models/openai/v1" &&
      output.chat_completions_endpoint == "${output.openai_base_url}/chat/completions" &&
      length(azapi_resource.runtime_api_key) == 1
    )
    error_message = "Reuse inbound Private Link/DNS and expose one shared endpoint with a gateway-wide runtime credential."
  }
}

run "disable_ai_gateway" {
  command = plan

  variables {
    ai_gateway_enabled = false
  }

  assert {
    condition = (
      length(azapi_resource.ai_gateway) == 0 &&
      length(azapi_resource.foundry_provider) == 0 &&
      length(azapi_resource.gateway_model) == 0 &&
      length(azapi_resource.model_alias) == 0 &&
      length(azapi_resource.runtime_api_key) == 0 &&
      length(azapi_resource_action.runtime_api_key_secrets) == 0 &&
      length(azurerm_role_assignment.foundry_user) == 0 &&
      length(azurerm_private_endpoint.ai_gateway) == 0 &&
      length(time_sleep.wait_for_foundry_rbac) == 0 &&
      output.gateway_url == null &&
      output.runtime_api_key == null
    )
    error_message = "Disabling this root must remove only its gateway resources and stop advertising its endpoint/key."
  }
}

run "reject_occupied_subnet" {
  command = plan

  override_data {
    target = data.azapi_resource_list.gateway_subnet_occupants[0]
    values = {
      output = {
        value = [{
          name = "apim-foundry-test01"
          properties = {
            virtualNetworkConfiguration = {
              subnetResourceId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-aigw-outbound"
            }
          }
        }]
      }
    }
  }

  expect_failures = [azapi_resource.ai_gateway[0]]
}

run "reject_invalid_gateway_name" {
  command = plan

  variables {
    gateway_name = "not a valid gateway"
  }

  expect_failures = [var.gateway_name]
}
