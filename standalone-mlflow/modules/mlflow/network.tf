locals {
  cfg      = var.settings
  name     = "${local.cfg.name}-${random_string.suffix.result}"
  app_name = "ca-${local.name}"
  tags     = merge({ managed_by = "terraform", workload = "litellm" }, local.cfg.tags)
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = coalesce(local.cfg.resource_group_name, "rg-${local.name}")
  location = local.cfg.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = local.cfg.location
  address_space       = [local.cfg.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "aca" {
  name                 = "container-apps"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.cfg.vnet_cidr, 7, 0)]
  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(local.cfg.vnet_cidr, 8, 2)]
  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "endpoints" {
  name                              = "private-endpoints"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [cidrsubnet(local.cfg.vnet_cidr, 11, 24)]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${local.name}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                = "postgres"
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  virtual_network_id  = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                = "redis"
  private_dns_zone_id = azurerm_private_dns_zone.redis.id
  virtual_network_id  = azurerm_virtual_network.this.id
}

# Internal ingress needs DNS for app, revision and label hostnames.
resource "azurerm_private_dns_zone" "aca" {
  count               = local.cfg.private_ingress ? 1 : 0
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca" {
  count               = local.cfg.private_ingress ? 1 : 0
  name                = "container-apps"
  private_dns_zone_id = azurerm_private_dns_zone.aca[0].id
  virtual_network_id  = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_a_record" "aca" {
  count               = local.cfg.private_ingress ? 1 : 0
  name                = "*"
  private_dns_zone_id = azurerm_private_dns_zone.aca[0].id
  ttl                 = 60
  records             = [azurerm_container_app_environment.this.static_ip_address]
}