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
    override_during = plan
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
      toset([for deployment in azurerm_cognitive_deployment.model : deployment.name]) ==
      toset(["FW-DeepSeek-V4.1-Flash", "gpt-6-astra", "FW-Kimi-K3", "Kimi-K3.1-Pro"]) &&
      toset([for deployment in azapi_resource.anthropic : deployment.name]) ==
      toset(["claude-opus-5-5"]) &&
      length(output.pending_models) == 0 &&
      toset([for model in values(output.gateway_foundation.models) : model.deployment_name]) ==
      toset(["claude-opus-5-5", "FW-DeepSeek-V4.1-Flash", "gpt-6-astra", "FW-Kimi-K3", "Kimi-K3.1-Pro"])
    )
    error_message = "Keep the five retained Foundry deployments and do not export retired models to the gateway."
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
      length(output.gateway_foundation.models) == 4
    )
    error_message = "Staging DeepSeek must exclude its deployment and advertise the quota dependency."
  }
}

run "deploys_kimi_at_approved_fireworks_maximum" {
  command = plan

  assert {
    condition = (
      azurerm_cognitive_deployment.model["kimi_k3"].name == "FW-Kimi-K3" &&
      azurerm_cognitive_deployment.model["kimi_k3"].model[0].format == "Fireworks" &&
      azurerm_cognitive_deployment.model["kimi_k3"].model[0].name == "FW-Kimi-K3" &&
      azurerm_cognitive_deployment.model["kimi_k3"].model[0].version == "1" &&
      azurerm_cognitive_deployment.model["kimi_k3"].sku[0].name == "GlobalStandard" &&
      azurerm_cognitive_deployment.model["kimi_k3"].sku[0].capacity == 500 &&
      azurerm_cognitive_deployment.model["kimi_k3"].version_upgrade_option == "NoAutoUpgrade" &&
      output.gateway_foundation.models.kimi_k3.capacity == 500 &&
      azurerm_cognitive_deployment.model["kimi_k3_1_pro"].model[0].format == "MoonshotAI" &&
      azurerm_cognitive_deployment.model["kimi_k3_1_pro"].model[0].version == "2026-11-04" &&
      azurerm_cognitive_deployment.model["kimi_k3_1_pro"].sku[0].name == "GlobalStandard" &&
      azurerm_cognitive_deployment.model["kimi_k3_1_pro"].version_upgrade_option == "NoAutoUpgrade" &&
      output.gateway_foundation.models.kimi_k3_1_pro.deployment_name == "Kimi-K3.1-Pro"
    )
    error_message = "Stage the pinned Moonshot model for gateway registration without changing the existing Fireworks deployment."
  }
}

run "preserves_standard_capacity_for_retained_models" {
  command = plan

  assert {
    condition = (
      merge(
        { for key, deployment in azurerm_cognitive_deployment.model : key => deployment.sku[0].capacity },
        { for key, deployment in azapi_resource.anthropic : key => deployment.body.sku.capacity },
        ) == {
        deepseek        = 250
        gpt6_astra      = 250
        kimi_k3         = 500
        kimi_k3_1_pro   = 100
        claude_opus_5_5 = 40
      } &&
      output.gateway_foundation.models.gpt6_astra.capacity == 250 &&
      output.gateway_foundation.models.claude_opus_5_5.capacity == 40 &&
      alltrue([for model in output.gateway_foundation.models : model.sku_name == "GlobalStandard"])
    )
    error_message = "Keep each retained model's capacity, gateway metadata, and pay-per-token GlobalStandard SKU."
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
