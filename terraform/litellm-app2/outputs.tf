output "chat_app2_url" {
  value = "https://${azurerm_linux_web_app.app2.default_hostname}/chat2"
}

output "litellm_url" {
  value = "https://${azurerm_container_app.litellm.ingress[0].fqdn}"
}

output "litellm_name" {
  value = azurerm_container_app.litellm.name
}

output "chat_app2_name" {
  value = azurerm_linux_web_app.app2.name
}

output "litellm_identity_principal_id" {
  value = azurerm_user_assigned_identity.litellm.principal_id
}

output "postgres_server_name" {
  value = azurerm_postgresql_flexible_server.litellm.name
}

output "postgres_database_name" {
  value = azurerm_postgresql_flexible_server_database.litellm.name
}

output "redis_name" {
  value = azurerm_managed_redis.litellm.name
}

output "redis_hostname" {
  value = azurerm_managed_redis.litellm.hostname
}

output "litellm_master_key" {
  value     = "sk-${random_password.proxy_key.result}"
  sensitive = true
}