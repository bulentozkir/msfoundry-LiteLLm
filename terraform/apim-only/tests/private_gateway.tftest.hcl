mock_provider "azurerm" {}

mock_provider "azapi" {
  mock_resource "azapi_resource_action" {
    defaults = {
      sensitive_output = {
        primaryKey = "mock-runtime-key"
      }
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

run "private_foundry_public_ai_gateway" {
  command = apply

  assert {
    condition = (
      azapi_resource.ai_gateway.body.sku.name == "AIGateway" &&
      azapi_resource.ai_gateway.body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.ai_gateway.body.properties.virtualNetworkType == "External" &&
      azapi_resource.ai_gateway.body.properties.virtualNetworkConfiguration.subnetResourceId == azurerm_subnet.ai_gateway_outbound.id
    )
    error_message = "Use the AIGateway preview tier with public ingress and outbound integration into its dedicated shared-VNet subnet."
  }

  assert {
    condition = (
      azapi_resource.foundry.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      azapi_resource.foundry.body.properties.networkAcls.bypass == "None" &&
      azapi_resource.foundry.body.properties.networkInjections[0].subnetArmId == azurerm_subnet.foundry_outbound.id
    )
    error_message = "Foundry must reject public access and local keys and configure outbound injection in its dedicated subnet."
  }

  assert {
    condition = (
      length(azurerm_cognitive_deployment.model) == 3 &&
      length(azapi_resource.gateway_model) == 3 &&
      length(azapi_resource.model_alias) == 3 &&
      length(azapi_resource.runtime_api_key) == 3
    )
    error_message = "Deploy exactly three Foundry models, gateway registrations, aliases, and independent runtime keys."
  }

  assert {
    condition = (
      azurerm_subnet.foundry_inbound.virtual_network_name == azurerm_virtual_network.shared.name &&
      azurerm_subnet.foundry_outbound.virtual_network_name == azurerm_virtual_network.shared.name &&
      azurerm_subnet.ai_gateway_outbound.virtual_network_name == azurerm_virtual_network.shared.name &&
      azurerm_subnet_network_security_group_association.ai_gateway_outbound.subnet_id == azurerm_subnet.ai_gateway_outbound.id &&
      azurerm_subnet_network_security_group_association.foundry_inbound.subnet_id == azurerm_subnet.foundry_inbound.id &&
      length(distinct(values(local.subnet_prefixes))) == 3 &&
      length(azurerm_private_dns_zone.foundry) == 3 &&
      length(azurerm_private_dns_zone_virtual_network_link.foundry) == 3
    )
    error_message = "Use three separate subnets in one shared VNet and link all three required Foundry private DNS zones."
  }
}
