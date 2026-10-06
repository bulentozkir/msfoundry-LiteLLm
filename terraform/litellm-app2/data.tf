resource "azurerm_postgresql_flexible_server" "litellm" {
  name                          = "psql-litellm-${var.name_suffix}"
  resource_group_name           = data.azurerm_resource_group.existing.name
  location                      = data.azurerm_resource_group.existing.location
  version                       = "16"
  sku_name                      = var.postgres_sku
  storage_mb                    = 32768
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  auto_grow_enabled             = false
  public_network_access_enabled = true
  zone                          = "1" # pin to the zone Azure already assigned; avoids a spurious restart-triggering update
  tags                          = var.tags

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = var.tenant_id
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_database" "litellm" {
  name      = "litellm"
  server_id = azurerm_postgresql_flexible_server.litellm.id

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "litellm" {
  server_name         = azurerm_postgresql_flexible_server.litellm.name
  resource_group_name = data.azurerm_resource_group.existing.name
  tenant_id           = var.tenant_id
  object_id           = azurerm_user_assigned_identity.litellm.principal_id
  principal_name      = azurerm_user_assigned_identity.litellm.name
  principal_type      = "ServicePrincipal"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "litellm" {
  for_each = var.postgres_allowed_ip_addresses

  name             = "litellm-${replace(each.value, ".", "-")}"
  server_id        = azurerm_postgresql_flexible_server.litellm.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

resource "azurerm_managed_redis" "litellm" {
  name                      = "redis-litellm-${var.name_suffix}"
  resource_group_name       = data.azurerm_resource_group.existing.name
  location                  = data.azurerm_resource_group.existing.location
  sku_name                  = var.redis_sku
  high_availability_enabled = false
  public_network_access     = "Enabled"
  tags                      = var.tags

  default_database {
    access_keys_authentication_enabled = false
    client_protocol                    = "Encrypted"
    clustering_policy                  = "NoCluster"
    eviction_policy                    = "NoEviction"
  }
}

resource "azurerm_managed_redis_access_policy_assignment" "litellm" {
  managed_redis_id = azurerm_managed_redis.litellm.id
  object_id        = azurerm_user_assigned_identity.litellm.principal_id
}

resource "random_password" "salt_key" {
  length  = 48
  special = false
}