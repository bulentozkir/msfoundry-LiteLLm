output "resource_group_name" {
  description = "Resource group containing all MLflow/Foundry test resources."
  value       = azurerm_resource_group.main.name
}

output "mlflow_model_alias" {
  description = "Model name to pass in chat completion requests against the proxy."
  value       = var.mlflow_model_alias
}

output "phi_deployment_name" {
  description = "Phi deployment in the existing Foundry account."
  value       = azurerm_cognitive_deployment.phi.name
}

output "postgres_server_fqdn" {
  description = "Private FQDN of the shared Postgres server (resolvable only from inside the VNet)."
  value       = azurerm_postgresql_flexible_server.mlflow.fqdn
}

output "mlflow_artifact_root" {
  description = "wasbs:// artifact-store URI passed to mlflow server --default-artifact-root."
  value       = "wasbs://${azurerm_storage_container.mlflow_artifacts.name}@${azurerm_storage_account.mlflow.name}.blob.core.windows.net/"
}

output "mlflow_acr_login_server" {
  description = "Container registry login server hosting the gateway image."
  value       = azurerm_container_registry.mlflow.login_server
}

output "mlflow_gateway_url" {
  description = "Public URL of the MLflow AI Gateway through Azure Front Door. The direct Container Apps origin is IP-restricted."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}"
}

output "mlflow_gateway_ui_url" {
  description = "MLflow UI/gateway endpoint via Front Door. Not authenticated beyond Front Door's IP allowlist - do not expose sensitive data here."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}/"
}

output "chat1_url" {
  description = "Public URL of chat1 (LiteLLM-backed) through Azure Front Door."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client1.host_name}"
}

output "chat1_phi_url" {
  description = "Phi chat URL on chat1 (LiteLLM-backed)."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client1.host_name}/chatphi"
}

output "litellm_redis_id" {
  description = "Resource ID of the dedicated LiteLLM Managed Redis instance (null when disabled)."
  value       = try(azurerm_managed_redis.litellm[0].id, null)
}

output "litellm_redis_hostname" {
  description = "Private hostname of the LiteLLM Managed Redis instance (null when disabled)."
  value       = try(azurerm_managed_redis.litellm[0].hostname, null)
}

output "litellm_redis_port" {
  description = "TLS port for LiteLLM Managed Redis (null when disabled)."
  value       = try(azurerm_managed_redis.litellm[0].default_database[0].port, null)
}

output "chat_client1_frontdoor_url" {
  description = "Public HTTPS URL of chat1 via the same Azure Front Door profile."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client1.host_name}"
}

output "chat_client2_url" {
  description = "Public URL of chat2 (MLflow-backed) through Azure Front Door."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client2.host_name}"
}

output "chat_phi_url" {
  description = "Phi chat URL on chat2 (MLflow-backed)."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client2.host_name}/chatphi"
}

output "chat_client2_frontdoor_url" {
  description = "Public HTTPS URL of chat-client2 via Azure Front Door Standard (the only public entry point - the App Service origin itself only accepts traffic from this Front Door)."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client2.host_name}"
}

output "chat_client3_url" {
  description = "Public URL of chat3 (APIM-backed) through Azure Front Door."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client3.host_name}"
}

output "chat3_phi_url" {
  description = "Phi chat URL on chat3 (APIM-backed)."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client3.host_name}/chat3phi"
}

output "chat_client3_frontdoor_url" {
  description = "Public HTTPS URL of chat3 via Azure Front Door Standard."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client3.host_name}"
}

output "apim_chat3_gateway_url" {
  description = "APIM Developer gateway base URL for chat3 API path."
  value       = "${trimsuffix(azurerm_api_management.chat3.gateway_url, "/")}/${azurerm_api_management_api.chat3_foundry.path}"
}

output "test_curl_command" {
  description = "Example request to smoke-test the deployed gateway through Azure Front Door once apply completes."
  value       = "curl -s https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}/gateway/mlflow/v1/chat/completions -H \"Content-Type: application/json\" -d '{\"model\": \"${var.mlflow_model_alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}]}'"
}

output "test_curl_litellm_command" {
  description = "Example request to smoke-test the LiteLLM flow used by chat1."
  value       = "curl -s ${trimsuffix(local.chat1_litellm_base_url, "/")}/chat/completions -H \"Content-Type: application/json\" -H \"Authorization: Bearer ${var.litellm_chat1_api_key}\" -d '{\"model\": \"${var.litellm_chat1_model_alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}]}'"
  sensitive   = true
}
