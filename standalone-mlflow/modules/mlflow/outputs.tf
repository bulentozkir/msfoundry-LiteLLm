output "connection" {
  description = "Nonsecret connection details for administrators and downstream integrations."
  value = {
    resource_group_name   = azurerm_resource_group.this.name
    container_app_name    = azurerm_container_app.this.name
    container_app_id      = azurerm_container_app.this.id
    proxy_url             = local.proxy_url
    admin_url             = "${local.proxy_url}/ui/"
    api_base_url          = "${local.proxy_url}/v1"
    revision_name         = azurerm_container_app.this.latest_revision_name
    identity_client_id    = azurerm_user_assigned_identity.this.client_id
    identity_principal_id = azurerm_user_assigned_identity.this.principal_id
    vnet_id               = azurerm_virtual_network.this.id
    postgres_server_name  = azurerm_postgresql_flexible_server.this.name
    postgres_hostname     = azurerm_postgresql_flexible_server.this.fqdn
    redis_hostname        = azurerm_managed_redis.this.hostname
  }
}

output "credentials" {
  description = "Generated bootstrap admin credentials; sensitive and persisted in state."
  sensitive   = true
  value = {
    ui_username = local.cfg.ui_username
    ui_password = random_password.ui.result
    master_key  = "sk-${random_password.master.result}"
  }
}