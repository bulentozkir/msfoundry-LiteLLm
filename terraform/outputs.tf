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
  description = "Direct Container Apps URL of the legacy MLflow gateway. Ingress remains restricted to VNet callers."
  value       = "https://${azurerm_container_app.mlflow_gateway.ingress[0].fqdn}"
}

output "mlflow_gateway_ui_url" {
  description = "Direct MLflow UI endpoint. Ingress remains restricted to VNet callers."
  value       = "https://${azurerm_container_app.mlflow_gateway.ingress[0].fqdn}/"
}

output "chat1_url" {
  description = "Direct App Service URL of legacy chat1 (LiteLLM-backed)."
  value       = "https://${azurerm_linux_web_app.chat_client1.default_hostname}"
}

output "chat1_phi_url" {
  description = "Phi chat URL on chat1 (LiteLLM-backed)."
  value       = "https://${azurerm_linux_web_app.chat_client1.default_hostname}/chatphi"
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

output "chat_client2_url" {
  description = "Direct App Service URL of legacy chat2 (MLflow-backed)."
  value       = "https://${azurerm_linux_web_app.chat_client2.default_hostname}"
}

output "chat_phi_url" {
  description = "Phi chat URL on chat2 (MLflow-backed)."
  value       = "https://${azurerm_linux_web_app.chat_client2.default_hostname}/chatphi"
}

output "test_curl_command" {
  description = "Example request to smoke-test the legacy gateway from an allowed VNet caller."
  value       = "curl -s https://${azurerm_container_app.mlflow_gateway.ingress[0].fqdn}/gateway/mlflow/v1/chat/completions -H \"Content-Type: application/json\" -d '{\"model\": \"${var.mlflow_model_alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}]}'"
}

output "test_curl_litellm_command" {
  description = "Example request to smoke-test the LiteLLM flow used by chat1."
  value       = "curl -s ${trimsuffix(local.chat1_litellm_base_url, "/")}/chat/completions -H \"Content-Type: application/json\" -H \"Authorization: Bearer ${var.litellm_chat1_api_key}\" -d '{\"model\": \"${var.litellm_chat1_model_alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}]}'"
  sensitive   = true
}
