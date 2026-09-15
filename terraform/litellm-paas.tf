# ---------------------------------------------------------------------------
# LiteLLM support PaaS resources.
#
# This root does not run LiteLLM itself. It can provision a private Managed
# Redis instance that an external LiteLLM runtime can use for shared state,
# throttling coordination, and cache-related features.
# ---------------------------------------------------------------------------

resource "azurerm_managed_redis" "litellm" {
  count                     = var.litellm_enable_paas_cache ? 1 : 0
  name                      = "redis-litellm-${random_string.suffix.result}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  sku_name                  = var.litellm_redis_sku
  high_availability_enabled = var.litellm_redis_high_availability
  public_network_access     = "Disabled"
  tags                      = merge(var.tags, { workload = "litellm" })

  default_database {
    access_keys_authentication_enabled = true
    client_protocol                    = "Encrypted"
    clustering_policy                  = "NoCluster"
    eviction_policy                    = "NoEviction"
  }
}

resource "azurerm_private_dns_zone" "litellm_redis" {
  count               = var.litellm_enable_paas_cache ? 1 : 0
  name                = "privatelink.redis.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "litellm_redis" {
  count               = var.litellm_enable_paas_cache ? 1 : 0
  name                = "link-litellm-redis"
  private_dns_zone_id = azurerm_private_dns_zone.litellm_redis[0].id
  virtual_network_id  = azurerm_virtual_network.main.id
}

resource "azurerm_private_endpoint" "litellm_redis" {
  count               = var.litellm_enable_paas_cache ? 1 : 0
  name                = "pe-litellm-redis-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = merge(var.tags, { workload = "litellm" })

  private_service_connection {
    name                           = "psc-litellm-redis"
    private_connection_resource_id = azurerm_managed_redis.litellm[0].id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "litellm-redis-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.litellm_redis[0].id]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.litellm_redis]
}
