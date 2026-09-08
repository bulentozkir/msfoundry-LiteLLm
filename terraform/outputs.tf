output "resource_group_name" {
  description = "Resource group containing all LiteLLM test resources."
  value       = azurerm_resource_group.main.name
}

output "litellm_url" {
  description = "Public URL of the LiteLLM proxy through Azure Front Door. The direct Container Apps origin is IP-restricted."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.litellm_admin.host_name}"
}

output "litellm_model_alias" {
  description = "Model name to pass in chat completion requests against the proxy."
  value       = var.litellm_model_alias
}

output "litellm_master_key" {
  description = "Bearer token for calling the LiteLLM proxy. Retrieve with: terraform output -raw litellm_master_key"
  value       = "sk-${random_password.litellm_master_key.result}"
  sensitive   = true
}

output "test_curl_command" {
  description = "Example request to smoke-test the deployed proxy through Azure Front Door once apply completes."
  value       = "curl -s https://${azurerm_cdn_frontdoor_endpoint.litellm_admin.host_name}/chat/completions -H \"Authorization: Bearer $(terraform output -raw litellm_master_key)\" -H \"Content-Type: application/json\" -d '{\"model\": \"${var.litellm_model_alias}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}]}'"
}
