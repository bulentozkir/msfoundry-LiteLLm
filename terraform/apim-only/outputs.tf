output "resource_group_name" {
  description = "Resource group containing the isolated architecture."
  value       = azurerm_resource_group.main.name
}

output "app3_url" {
  description = "Direct public HTTPS endpoint for app3."
  value       = "https://${azurerm_linux_web_app.app3.default_hostname}"
}

output "ai_gateway_base_url" {
  description = "OpenAI-compatible base URL exposed by the APIM AI Gateway tier."
  value       = local.ai_gateway_openai_base_url
}

output "ai_gateway_portal_url" {
  description = "Dedicated AI Gateway management portal."
  value       = "https://ai.gateway.azure.com"
}

output "foundry_account_id" {
  description = "ARM ID of the Microsoft Foundry account."
  value       = azurerm_cognitive_account.foundry.id
}

output "model_deployments" {
  description = "Client-facing deployment names routed through AI Gateway."
  value       = [for model in local.models : model.deployment_name]
}

output "deepseek_user_deployments" {
  description = "Per-user Foundry deployment names; these are not published through AI Gateway."
  value = {
    for user_id, deployment in azurerm_cognitive_deployment.deepseek_user :
    user_id => deployment.name
  }
}

output "opencode_api_key" {
  description = "Runtime access key for local OpenCode configuration."
  value       = azapi_resource_action.opencode_api_key_secrets.sensitive_output.primaryKey
  sensitive   = true
}

output "zed_api_key" {
  description = "Runtime access key for the local Zed OpenAI-compatible provider."
  value       = azapi_resource_action.zed_api_key_secrets.sensitive_output.primaryKey
  sensitive   = true
}
