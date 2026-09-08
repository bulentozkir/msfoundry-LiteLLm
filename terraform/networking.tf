# ---------------------------------------------------------------------------
# VNet + subnets: makes all access to LiteLLM (Container Apps), the chat
# client (App Service), and Microsoft Foundry private. No component in this
# stack is reachable over the public internet after this file's resources
# are applied - see README notes on required in-VNet access (VPN/Bastion) for
# actual end-user use afterward.
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.20.0.0/16"]
  tags                = var.tags
}

# Container Apps Consumption-only environments require a /23 minimum when
# using a custom infrastructure subnet.
resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.0.0/23"]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private Endpoints for Foundry + the chat client App Service.
resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.2.0/27"]

  private_endpoint_network_policies = "Disabled"
}

# App Service regional VNet Integration (outbound) - must be a different
# subnet from the Private Endpoint subnet.
resource "azurerm_subnet" "appsvc" {
  name                 = "snet-appsvc"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.2.32/27"]

  delegation {
    name = "appsvc-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# ---------------------------------------------------------------------------
# Private DNS zones - Foundry account (all 3 FQDNs it exposes) + the
# Container Apps environment's internal domain + App Service.
# ---------------------------------------------------------------------------

locals {
  foundry_private_dns_zone_names = [
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com",
  ]
}

resource "azurerm_private_dns_zone" "foundry" {
  for_each            = toset(local.foundry_private_dns_zone_names)
  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "foundry" {
  for_each            = azurerm_private_dns_zone.foundry
  name                = "link-${replace(each.key, ".", "-")}"
  private_dns_zone_id = each.value.id
  virtual_network_id  = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_zone" "app_service" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "app_service" {
  name                = "link-appsvc"
  private_dns_zone_id = azurerm_private_dns_zone.app_service.id
  virtual_network_id  = azurerm_virtual_network.main.id
}

# Container Apps environment's internal domain: Microsoft's own guidance is
# to create a zone matching the environment's auto-generated default_domain
# with a wildcard A record at the environment's static IP.
resource "azurerm_private_dns_zone" "aca_internal" {
  name                = azurerm_container_app_environment.main.default_domain
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca_internal" {
  name                = "link-aca-internal"
  private_dns_zone_id = azurerm_private_dns_zone.aca_internal.id
  virtual_network_id  = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_a_record" "aca_internal_wildcard" {
  name                = "*"
  private_dns_zone_id = azurerm_private_dns_zone.aca_internal.id
  ttl                 = 300
  records             = [azurerm_container_app_environment.main.static_ip_address]
}
