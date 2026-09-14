output "resource_group_name" {
  description = "Resource group containing all MLflow/Foundry test resources."
  value       = azurerm_resource_group.main.name
}

output "mlflow_model_alias" {
  description = "Model name to pass in chat completion requests against the proxy."
  value       = var.mlflow_model_alias
}

output "test_curl_command" {
  description = "Example request to smoke-test the deployed gateway through Azure Front Door once apply completes."
  value       = "curl -s https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}/gateway/mlflow/v1/chat/completions -H \"Content-Type: application/json\" -d '{\"model\": \"${var.mlflow_model_alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}]}'"
}
