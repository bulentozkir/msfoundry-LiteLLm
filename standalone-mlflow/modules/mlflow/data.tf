resource "random_password" "postgres" {
  length  = 40
  special = false
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "psql-${local.name}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = local.cfg.location
  version                       = "16"
  sku_name                      = local.cfg.postgres_sku
  storage_mb                    = local.cfg.postgres_storage_mb
  backup_retention_days         = local.cfg.postgres_backup_days
  administrator_login           = "litellmadmin"
  administrator_password        = random_password.postgres.result
  delegated_subnet_id           = azurerm_subnet.postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  tags                          = local.tags

  dynamic "high_availability" {
    for_each = local.cfg.postgres_ha_mode == null ? [] : [local.cfg.postgres_ha_mode]
    content {
      mode = high_availability.value
    }
  }

  lifecycle {
    prevent_destroy = true
  }
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = "litellm"
  server_id = azurerm_postgresql_flexible_server.this.id
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_managed_redis" "this" {
  name                      = "redis-${local.name}"
  resource_group_name       = azurerm_resource_group.this.name
  location                  = local.cfg.location
  sku_name                  = local.cfg.redis_sku
  high_availability_enabled = local.cfg.redis_high_availability
  public_network_access     = "Disabled"
  tags                      = local.tags
  default_database {
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    clustering_policy                  = "NoCluster"
    eviction_policy                    = "NoEviction"
  }
}

resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = local.cfg.location
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags
  private_service_connection {
    name                           = "redis"
    private_connection_resource_id = azurerm_managed_redis.this.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "redis"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }
}