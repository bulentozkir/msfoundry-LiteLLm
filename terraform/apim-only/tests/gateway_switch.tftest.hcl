variables {
  standard_gateway_enabled = true
  claude_provider_data = {
    organizationName = "Contoso"
    countryCode      = "SE"
    industry         = "technology"
  }
}

mock_provider "azurerm" {}
mock_provider "time" {}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "22222222-2222-4222-8222-222222222222"
    }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    override_during = plan
    defaults = {
      id     = "test01"
      result = "test01"
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

run "disable_only_standard_gateway" {
  command = plan

  variables {
    standard_gateway_enabled = false
    entra_model_principal_ids = {
      gpt5_4_mini = ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]
    }
  }

  assert {
    condition = (
      length(azapi_resource.apim) == 0 &&
      length(azurerm_role_assignment.apim_foundry_user) == 0 &&
      length(time_sleep.wait_for_apim_foundry_rbac) == 0 &&
      length(azurerm_private_endpoint.apim) == 0 &&
      length(azurerm_api_management_api.model) == 0 &&
      length(azurerm_api_management_api.entra_model) == 0 &&
      length(azurerm_api_management_api_policy.model) == 0 &&
      length(azurerm_api_management_api_policy.entra_model) == 0 &&
      length(azurerm_api_management_api_tag.model) == 0 &&
      length(azurerm_api_management_api_tag.entra_model) == 0 &&
      length(azurerm_api_management_tag.ai_model) == 0 &&
      length(azurerm_api_management_subscription.model) == 0 &&
      length(azurerm_api_management_product.model) == 0 &&
      length(azurerm_api_management_product_api.model) == 0 &&
      length(azurerm_api_management_product_group.model) == 0 &&
      length(azapi_resource.model_backend) == 0
    )
    error_message = "Disabling Standard v2 must remove all and only its gateway-specific resources."
  }

  assert {
    condition = (
      length(azurerm_cognitive_deployment.model) == 3 &&
      length(azurerm_cognitive_deployment.additional) == 3 &&
      azapi_resource.claude_opus_5_5.name == "claude-opus-5-5" &&
      azapi_resource.foundry.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      azurerm_virtual_network.shared.address_space == toset(["10.42.0.0/16"]) &&
      length(local.subnet_prefixes) == 4 &&
      length(azurerm_private_dns_zone.foundry) == 3 &&
      azurerm_private_dns_zone.ai_gateway.name == "privatelink.azure-api.net" &&
      length(azuread_application.model_access.app_role) == 3 &&
      length(azuread_app_role_assignment.model) == 1
    )
    error_message = "Retain Foundry, all seven deployments, shared networking, DNS, and the unchanged three-role Entra registration and assignments."
  }

  assert {
    condition = (
      output.apim_gateway_url == null &&
      output.apim_portal_url == null &&
      length(output.apim_subscription_keys) == 0 &&
      length(output.apim_model_endpoints) == 0 &&
      length(output.apim_entra_model_endpoints) == 0 &&
      length(output.apim_model_product_ids) == 0 &&
      length(output.apim_model_backend_ids) == 0 &&
      length(output.apim_subscription_ids) == 0 &&
      !output.gateway_foundation.standard_gateway_enabled &&
      length(output.gateway_foundation.models) == 7 &&
      length(output.apim_entra_authentication.model_roles) == 3
    )
    error_message = "Do not advertise disabled Standard endpoints or keys; continue exporting nonsecret foundation and retained Entra metadata."
  }
}

run "alternate_name_preserves_entra_registration" {
  command = plan

  variables {
    gateway_name = "apim-standard-test01-new"
  }

  assert {
    condition = (
      azapi_resource.apim[0].name == "apim-standard-test01-new" &&
      azuread_application.model_access.display_name == "apim-foundry-test01-model-access" &&
      contains(azuread_application.model_access.identifier_uris, "api://${var.tenant_id}/apim-foundry-test01")
    )
    error_message = "Recreating Standard v2 with a new service name must preserve its Entra audience, registration, and role identifiers."
  }
}
