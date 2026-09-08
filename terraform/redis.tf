# Lowest-cost managed Redis for this test environment. Non-HA has no SLA:
# restarts/outages can lose coordination state. PostgreSQL remains the durable
# store. Do not use this topology for production hard-budget enforcement.
resource "azurerm_managed_redis" "litellm" {
  name                      = "redis-${var.project_name}-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  sku_name                  = "Balanced_B0"
  high_availability_enabled = false
  public_network_access     = "Disabled"
  tags                      = var.tags

  default_database {
    # LiteLLM uses redis-py password auth; Azure generates the access keys.
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    # Preserve multi-key transactions without cross-slot limitations.
    clustering_policy = "NoCluster"
    # Do not silently evict budget/rate-limit counters under memory pressure.
    eviction_policy = "NoEviction"
  }
}

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name               = "link-redis"
  private_dns_zone_id = azurerm_private_dns_zone.redis.id
  virtual_network_id = azurerm_virtual_network.main.id
}

resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-redis"
    private_connection_resource_id = azurerm_managed_redis.litellm.id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }
}

output "redis_hostname" {
  description = "Private-only Azure Managed Redis hostname; TLS required. No access keys are output."
  value       = azurerm_managed_redis.litellm.hostname
}