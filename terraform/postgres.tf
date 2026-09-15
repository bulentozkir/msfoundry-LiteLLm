# ---------------------------------------------------------------------------
# Postgres, reused as-is for the MLflow gateway's backend store (tracking
# metadata - see mlflow-gateway.tf for the mlflow database on this same
# server). The old litellm database is dropped; nothing else read it.
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

resource "azurerm_postgresql_flexible_server" "mlflow" {
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

  storage_mb = 32768
  sku_name   = "B_Standard_B1ms"

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

moved {
  from = azurerm_postgresql_flexible_server.litellm
  to   = azurerm_postgresql_flexible_server.mlflow
}
