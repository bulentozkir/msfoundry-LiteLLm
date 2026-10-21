locals {
  vnet_address_space = "10.42.0.0/16"
  subnet_prefixes = {
    foundry_inbound     = cidrsubnet(local.vnet_address_space, 8, 0)
    foundry_outbound    = cidrsubnet(local.vnet_address_space, 8, 1)
    ai_gateway_outbound = cidrsubnet(local.vnet_address_space, 8, 2)
    ai_gateway_inbound  = cidrsubnet(local.vnet_address_space, 8, 3)
  }
  foundry_private_dns_zones = toset([
    "privatelink.services.ai.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.cognitiveservices.azure.com",
  ])
  ai_gateway_outbound_destinations = {
    storage = {
      priority    = 100
      destination = "Storage"
    }
    keyvault = {
      priority    = 110
      destination = "AzureKeyVault"
    }
    foundry = {
      priority    = 120
      destination = local.subnet_prefixes.foundry_inbound
    }
  }
}

resource "azurerm_virtual_network" "shared" {
  name                = "vnet-foundry-aigw-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [local.vnet_address_space]
  tags                = var.tags
}

resource "azurerm_network_security_group" "foundry_inbound" {
  name                = "nsg-foundry-inbound-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "foundry_private_https" {
  name                        = "Allow-Gateway-And-Foundry-HTTPS"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.foundry_inbound.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefixes = [
    local.subnet_prefixes.ai_gateway_outbound,
    local.subnet_prefixes.foundry_outbound,
  ]
  destination_address_prefix = local.subnet_prefixes.foundry_inbound
}

resource "azurerm_network_security_rule" "foundry_deny_other_inbound" {
  name                        = "Deny-Other-Inbound"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.foundry_inbound.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_group" "ai_gateway_outbound" {
  name                = "nsg-aigw-outbound-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "ai_gateway_outbound" {
  for_each = local.ai_gateway_outbound_destinations

  name                        = "Allow-${each.key}-HTTPS"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.ai_gateway_outbound.name
  priority                    = each.value.priority
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = local.subnet_prefixes.ai_gateway_outbound
  destination_address_prefix  = each.value.destination
}

resource "azurerm_subnet" "foundry_inbound" {
  name                              = "snet-foundry-inbound"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.shared.name
  address_prefixes                  = [local.subnet_prefixes.foundry_inbound]
  private_endpoint_network_policies = "NetworkSecurityGroupEnabled"

  depends_on = [
    azurerm_network_security_rule.foundry_private_https,
    azurerm_network_security_rule.foundry_deny_other_inbound,
  ]
}

resource "azurerm_subnet" "foundry_outbound" {
  name                 = "snet-foundry-outbound"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.shared.name
  address_prefixes     = [local.subnet_prefixes.foundry_outbound]

  delegation {
    name = "foundry-agent-injection"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "ai_gateway_outbound" {
  name                 = "snet-aigw-outbound"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.shared.name
  address_prefixes     = [local.subnet_prefixes.ai_gateway_outbound]

  delegation {
    name = "ai-gateway-outbound-integration"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "foundry_inbound" {
  subnet_id                 = azurerm_subnet.foundry_inbound.id
  network_security_group_id = azurerm_network_security_group.foundry_inbound.id
}

resource "azurerm_subnet_network_security_group_association" "ai_gateway_outbound" {
  subnet_id                 = azurerm_subnet.ai_gateway_outbound.id
  network_security_group_id = azurerm_network_security_group.ai_gateway_outbound.id
}

resource "azurerm_private_dns_zone" "foundry" {
  for_each = local.foundry_private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "foundry" {
  for_each = local.foundry_private_dns_zones

  name                 = "foundry-shared-vnet"
  private_dns_zone_id  = azurerm_private_dns_zone.foundry[each.key].id
  virtual_network_id   = azurerm_virtual_network.shared.id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_private_endpoint" "foundry" {
  name                = "pe-foundry-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.foundry_inbound.id
  tags                = var.tags

  private_service_connection {
    name                           = "foundry-account"
    private_connection_resource_id = azapi_resource.foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "foundry"
    private_dns_zone_ids = [for zone in azurerm_private_dns_zone.foundry : zone.id]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.foundry,
    azurerm_subnet_network_security_group_association.foundry_inbound,
  ]
}

resource "azurerm_network_security_group" "ai_gateway_inbound" {
  name                = "nsg-aigw-inbound-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "ai_gateway_private_https" {
  name                        = "Allow-VNet-HTTPS"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.ai_gateway_inbound.name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = local.subnet_prefixes.ai_gateway_inbound
}

resource "azurerm_network_security_rule" "ai_gateway_deny_other_inbound" {
  name                        = "Deny-Other-Inbound"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.ai_gateway_inbound.name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet" "ai_gateway_inbound" {
  name                              = "snet-aigw-inbound"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.shared.name
  address_prefixes                  = [local.subnet_prefixes.ai_gateway_inbound]
  private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
}

resource "azurerm_subnet_network_security_group_association" "ai_gateway_inbound" {
  subnet_id                 = azurerm_subnet.ai_gateway_inbound.id
  network_security_group_id = azurerm_network_security_group.ai_gateway_inbound.id

  depends_on = [
    azurerm_network_security_rule.ai_gateway_private_https,
    azurerm_network_security_rule.ai_gateway_deny_other_inbound,
  ]
}

resource "azurerm_private_dns_zone" "ai_gateway" {
  name                = "privatelink.azure-api.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "ai_gateway" {
  name                 = "ai-gateway-shared-vnet"
  private_dns_zone_id  = azurerm_private_dns_zone.ai_gateway.id
  virtual_network_id   = azurerm_virtual_network.shared.id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_private_endpoint" "apim" {
  count = var.standard_gateway_enabled ? 1 : 0

  name                = "pe-apim-inbound-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.ai_gateway_inbound.id
  tags                = var.tags

  private_service_connection {
    name                           = "apim-inbound"
    private_connection_resource_id = azapi_resource.apim[0].id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "apim"
    private_dns_zone_ids = [azurerm_private_dns_zone.ai_gateway.id]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.ai_gateway,
    azurerm_subnet_network_security_group_association.ai_gateway_inbound,
  ]
}
