variables {
  standard_gateway_enabled = true
  claude_provider_data = {
    organizationName = "Contoso"
    countryCode      = "SE"
    industry         = "technology"
  }
}

mock_provider "azurerm" {}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "22222222-2222-4222-8222-222222222222"
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

  mock_data "azapi_resource_list" {
    defaults = {
      output = { value = [] }
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

mock_provider "time" {}

run "private_foundry_public_standard_apim" {
  command = plan

  assert {
    condition = (
      azapi_resource.apim[0].body.sku.name == "StandardV2" &&
      azapi_resource.apim[0].body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.apim[0].body.properties.virtualNetworkType == "External" &&
      contains(keys(azapi_resource.apim[0].body.properties.virtualNetworkConfiguration), "subnetResourceId")
    )
    error_message = "Use Standard v2 APIM with public ingress and outbound integration into its dedicated shared-VNet subnet."
  }

  assert {
    condition = (
      azapi_resource.foundry.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      azapi_resource.foundry.body.properties.networkAcls.bypass == "AzureServices" &&
      azapi_resource.foundry.body.properties.networkAcls.defaultAction == "Deny" &&
      azapi_resource.foundry.body.properties.networkInjections[0].scenario == "agent" &&
      !azapi_resource.foundry.body.properties.networkInjections[0].useMicrosoftManagedNetwork &&
      contains(keys(azapi_resource.foundry.body.properties.networkInjections[0]), "subnetArmId")
    )
    error_message = "Foundry must enable the trusted Azure services exception while keeping public access and local keys disabled, default network access denied, and outbound injection in its dedicated subnet."
  }

  assert {
    condition = (
      azapi_resource_action.fireworks_registration.type == "Microsoft.CognitiveServices/features@2021-07-01" &&
      azapi_resource_action.fireworks_registration.resource_id == "/subscriptions/${var.subscription_id}/providers/Microsoft.Features/providers/Microsoft.CognitiveServices/features/Fireworks.EnableDeploy" &&
      azapi_resource_action.fireworks_registration.action == "register" &&
      azapi_resource_action.fireworks_registration.method == "POST"
    )
    error_message = "Register the required Fireworks feature in the existing subscription without changing Foundry authentication or networking."
  }

  assert {
    condition = (
      length(azurerm_cognitive_deployment.model) == 3 &&
      length(azurerm_api_management_api.model) == 3 &&
      length(azurerm_api_management_api_policy.model) == 3 &&
      length(azurerm_api_management_subscription.model) == 3
    )
    error_message = "Preserve the original three deployments and their Standard APIs, policies, and subscriptions."
  }

  assert {
    condition = (
      toset([for deployment in azurerm_cognitive_deployment.model : deployment.name]) ==
      toset(["Gpt5.4mini", "Phi", "FW-DeepSeek-V4.1-Flash"]) &&
      toset([for deployment in azurerm_cognitive_deployment.model : deployment.model[0].name]) ==
      toset(["gpt-5.4-mini", "Phi-4", "DeepSeek-V4-Flash"])
    )
    error_message = "Deploy exactly one GPT mini, one Phi, and one DeepSeek Flash using the expected deployment names and catalog models."
  }

  assert {
    condition = (
      length(azurerm_cognitive_deployment.additional) == 3 &&
      azurerm_cognitive_deployment.additional["gpt6_astra"].model[0].name == "gpt-6-astra" &&
      azurerm_cognitive_deployment.additional["gpt6_astra"].model[0].version == "2026-09-03" &&
      azurerm_cognitive_deployment.additional["glm5_3_flash"].model[0].name == "FW-GLM-5.3-Flash" &&
      azurerm_cognitive_deployment.additional["kimi_k3"].model[0].name == "FW-Kimi-K3" &&
      alltrue([
        for deployment in azurerm_cognitive_deployment.additional :
        deployment.sku[0].name == "GlobalStandard" &&
        deployment.sku[0].capacity == 10 &&
        deployment.version_upgrade_option == "NoAutoUpgrade"
      ]) &&
      azapi_resource.claude_opus_5_5.name == "claude-opus-5-5" &&
      azapi_resource.claude_opus_5_5.body.properties.model.format == "Anthropic" &&
      azapi_resource.claude_opus_5_5.body.properties.model.version == "2" &&
      azapi_resource.claude_opus_5_5.body.properties.modelProviderData == var.claude_provider_data &&
      azapi_resource.claude_opus_5_5.body.properties.versionUpgradeOption == "NoAutoUpgrade" &&
      azapi_resource.claude_opus_5_5.body.sku.name == "GlobalStandard" &&
      azapi_resource.claude_opus_5_5.body.sku.capacity == 10 &&
      length(output.gateway_foundation.models) == 7 &&
      toset(output.model_deployments) == toset(["Gpt5.4mini", "Phi", "FW-DeepSeek-V4.1-Flash", "claude-opus-5-5", "gpt-6-astra", "FW-GLM-5.3-Flash", "FW-Kimi-K3"])
    )
    error_message = "Add exactly the four requested pay-as-you-go models, pin their versions, and pass the explicit Claude Marketplace attestation without changing legacy Standard access."
  }

  assert {
    condition = (
      length(azurerm_virtual_network.shared.address_space) == 1 &&
      contains(azurerm_virtual_network.shared.address_space, "10.42.0.0/16") &&
      contains(azurerm_subnet.foundry_inbound.address_prefixes, "10.42.0.0/24") &&
      contains(azurerm_subnet.foundry_outbound.address_prefixes, "10.42.1.0/24") &&
      contains(azurerm_subnet.ai_gateway_outbound.address_prefixes, "10.42.2.0/24") &&
      contains(azurerm_subnet.ai_gateway_inbound.address_prefixes, "10.42.3.0/24") &&
      azurerm_subnet.foundry_outbound.delegation[0].service_delegation[0].name == "Microsoft.App/environments" &&
      azurerm_subnet.ai_gateway_outbound.delegation[0].service_delegation[0].name == "Microsoft.Web/serverFarms" &&
      length(distinct(values(local.subnet_prefixes))) == 4 &&
      length(azurerm_private_dns_zone.foundry) == 3 &&
      length(azurerm_private_dns_zone_virtual_network_link.foundry) == 3 &&
      azurerm_private_dns_zone.ai_gateway.name == "privatelink.azure-api.net" &&
      contains(azurerm_private_endpoint.apim[0].private_service_connection[0].subresource_names, "Gateway")
    )
    error_message = "Use four separate subnets in one shared VNet, the Foundry private DNS zones, and a Gateway private endpoint with its private DNS zone."
  }
}

run "reject_invalid_claude_attestation" {
  command = plan

  variables {
    claude_provider_data = {
      organizationName = " "
      countryCode      = "Sweden"
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

  expect_failures = [
    azurerm_cognitive_deployment.additional["glm5_3_flash"],
    azurerm_cognitive_deployment.additional["kimi_k3"],
  ]
}
