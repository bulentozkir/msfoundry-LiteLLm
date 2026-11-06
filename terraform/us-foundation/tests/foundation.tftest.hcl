variables {
  claude_provider_data = {
    organizationName = "Contoso"
    countryCode      = "US"
    industry         = "technology"
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway"
      name     = "rg-foundry-aigateway"
      location = "eastus2"
      tags     = {}
    }
  }
}

mock_provider "azapi" {
  mock_data "azapi_resource" {
    override_during = plan
    defaults = {
      output = { properties = { state = "Registered" } }
    }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = {
      result = "test01"
    }
  }
}

run "preserves_private_foundry_and_requested_models" {
  command = plan

  assert {
    condition = (
      azapi_resource.foundry.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      azapi_resource.foundry.body.properties.networkAcls.bypass == "AzureServices" &&
      azapi_resource.foundry.body.properties.networkAcls.defaultAction == "Deny" &&
      azapi_resource.foundry.body.properties.networkInjections[0].scenario == "agent" &&
      !azapi_resource.foundry.body.properties.networkInjections[0].useMicrosoftManagedNetwork
    )
    error_message = "Keep the Foundry account private, disable local authentication, and retain its agent subnet injection."
  }

  assert {
    condition = (
      toset(concat(
        [for deployment in azurerm_cognitive_deployment.model : deployment.name],
        [azapi_resource.model_router.name],
      )) ==
      toset(["model-router", "FW-DeepSeek-V4.1-Flash", "gpt-6-astra", "FW-Kimi-K3", "gpt-chat-latest"]) &&
      toset([for deployment in azapi_resource.anthropic : deployment.name]) ==
      toset(["claude-opus-5-5", "claude-opus-5-5-fast"]) &&
      !contains(keys(azurerm_cognitive_deployment.model), "qwen") &&
      length(output.pending_models) == 0 &&
      length(output.gateway_foundation.models) == 7
    )
    error_message = "Deploy the requested available models with the Standard-quota replacement, without Qwen, Phi, GPT mini, GLM, or Claude Fable."
  }

  assert {
    condition = (
      azurerm_subnet.foundry_outbound.delegation[0].service_delegation[0].name == "Microsoft.App/environments" &&
      azurerm_subnet.ai_gateway_outbound.delegation[0].service_delegation[0].name == "Microsoft.App/environments" &&
      length(distinct(values(local.subnet_prefixes))) == 4 &&
      length(azurerm_private_dns_zone.foundry) == 3 &&
      contains(azurerm_private_endpoint.foundry.private_service_connection[0].subresource_names, "account")
    )
    error_message = "Keep separate Foundry and gateway subnets, required delegation, Foundry private DNS, and the Foundry private endpoint."
  }
}

run "stages_deepseek_without_quota" {
  command = plan

  variables {
    enable_deepseek = false
  }

  assert {
    condition = (
      !contains(keys(azurerm_cognitive_deployment.model), "deepseek") &&
      contains(keys(output.pending_models), "FW-DeepSeek-V4.1-Flash") &&
      length(output.gateway_foundation.models) == 6
    )
    error_message = "Staging DeepSeek must exclude its deployment and advertise the quota dependency."
  }
}

run "deploys_latest_chat_model_with_standard_quota" {
  command = plan

  assert {
    condition = (
      azurerm_cognitive_deployment.model["gpt_chat_latest"].name == "gpt-chat-latest" &&
      azurerm_cognitive_deployment.model["gpt_chat_latest"].model[0].format == "OpenAI" &&
      azurerm_cognitive_deployment.model["gpt_chat_latest"].model[0].name == "gpt-chat-latest" &&
      azurerm_cognitive_deployment.model["gpt_chat_latest"].model[0].version == "2026-10-07" &&
      azurerm_cognitive_deployment.model["gpt_chat_latest"].sku[0].name == "GlobalStandard" &&
      azurerm_cognitive_deployment.model["gpt_chat_latest"].sku[0].capacity == 10 &&
      azurerm_cognitive_deployment.model["gpt_chat_latest"].version_upgrade_option == "NoAutoUpgrade" &&
      output.gateway_foundation.models.gpt_chat_latest.deployment_name == "gpt-chat-latest" &&
      output.gateway_foundation.models.gpt_chat_latest.version == "2026-10-07" &&
      output.gateway_foundation.models.gpt_chat_latest.sku_name == "GlobalStandard" &&
      output.gateway_foundation.models.gpt_chat_latest.capacity == 10 &&
      length(output.pending_models) == 0 &&
      length(output.gateway_foundation.models) == 7
    )
    error_message = "Deploy the pinned latest chat model with pay-per-token Standard capacity and expose its exact metadata to the gateway."
  }
}

run "reject_invalid_claude_attestation" {
  command = plan

  variables {
    claude_provider_data = {
      organizationName = " "
      countryCode      = "United States"
      industry         = "software"
    }
  }

  expect_failures = [var.claude_provider_data]
}

run "reject_pending_fireworks_registration" {
  command = plan

  override_data {
    target          = data.azapi_resource.fireworks_feature
    override_during = plan
    values = {
      output = { properties = { state = "Registering" } }
    }
  }

  expect_failures = [azurerm_cognitive_deployment.model["kimi_k3"]]
}
