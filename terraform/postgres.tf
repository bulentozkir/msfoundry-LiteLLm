# ---------------------------------------------------------------------------
# Postgres for LiteLLM's Admin UI + spend/token-usage tracking (per-key, i.e.
# per-app since ca-litellm and ca-litellm2 each use a distinct master key).
# Cheapest viable SKU (Burstable B1ms, 32GB min storage) - this is a test/demo
# environment, not production. VNet-integrated (delegated subnet + private
# DNS zone) to match the rest of the stack's private-only access model - no
# public network access, consistent with everything else here.
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.3.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                = "link-postgres"
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  virtual_network_id  = azurerm_virtual_network.main.id
}

resource "random_password" "postgres_admin_password" {
  length  = 32
  special = false
}

resource "azurerm_postgresql_flexible_server" "litellm" {
  name                = "psql-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags

  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  administrator_login    = "litellmadmin"
  administrator_password = random_password.postgres_admin_password.result

  storage_mb   = 32768
  sku_name     = "B_Standard_B1ms"

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "litellm" {
  name      = "litellm"
  server_id = azurerm_postgresql_flexible_server.litellm.id
}

locals {
  litellm_database_url = "postgresql://${azurerm_postgresql_flexible_server.litellm.administrator_login}:${random_password.postgres_admin_password.result}@${azurerm_postgresql_flexible_server.litellm.fqdn}:5432/${azurerm_postgresql_flexible_server_database.litellm.name}?sslmode=require"
}

output "postgres_server_fqdn" {
  description = "Private FQDN of the LiteLLM Postgres server (resolvable only from inside the VNet)."
  value       = azurerm_postgresql_flexible_server.litellm.fqdn
}
