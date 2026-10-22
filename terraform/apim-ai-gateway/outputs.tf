output "ai_gateway_enabled" {
  description = "Whether this root manages an active AI Gateway instance."
  value       = var.ai_gateway_enabled
}

output "gateway_id" {
  description = "ARM ID of the AI Gateway pricing-tier instance."
  value       = var.ai_gateway_enabled ? azapi_resource.ai_gateway[0].id : null
}

output "gateway_url" {
  description = "Public HTTPS gateway URL; private clients use the same hostname."
  value       = var.ai_gateway_enabled ? "https://${local.ai_gateway_name}.azure-api.net" : null
}

output "openai_base_url" {
  description = "Shared base URL for the registered OpenAI-compatible models; Claude uses the Anthropic endpoint."
  value       = var.ai_gateway_enabled ? local.openai_base_url : null
}

output "chat_completions_endpoint" {
  description = "Shared OpenAI-compatible chat endpoint. Select an exact registered name in the model field; Claude uses messages_endpoint."
  value       = var.ai_gateway_enabled ? "${local.openai_base_url}/chat/completions" : null
}

output "anthropic_base_url" {
  description = "Native Anthropic SDK base URL for Claude, without the /v1/messages operation path."
  value       = var.ai_gateway_enabled ? local.anthropic_base_url : null
}

output "messages_endpoint" {
  description = "Native Anthropic Messages endpoint; send anthropic-version and the gateway runtime key."
  value       = var.ai_gateway_enabled ? "${local.anthropic_base_url}/v1/messages" : null
}

output "model_endpoints" {
  description = "Correct native completion endpoint for each published deployment."
  value = {
    for model in local.models :
    model.deployment_name => model.format == "Anthropic" ? "${local.anthropic_base_url}/v1/messages" : "${local.openai_base_url}/chat/completions"
  }
}

output "portal_url" {
  description = "Azure portal page for the AI Gateway Azure resource."
  value       = var.ai_gateway_enabled ? "https://portal.azure.com/#resource${azapi_resource.ai_gateway[0].id}/overview" : null
}

output "ai_gateway_portal_url" {
  description = "Standalone portal for AI Gateway models, runtime keys, and networking."
  value       = "https://ai.gateway.azure.com"
}

output "model_deployments" {
  description = "All retained and additional Foundry deployments registered in this gateway."
  value       = [for model in local.models : model.deployment_name]
}

output "runtime_api_key" {
  description = "Gateway-wide runtime key; send in api-key. It is NOT restricted to an individual model."
  value       = var.ai_gateway_enabled ? azapi_resource_action.runtime_api_key_secrets[0].sensitive_output.primaryKey : null
  sensitive   = true
}

output "foundation" {
  description = "Nonsecret foundation IDs for operational verification. Ownership remains with apim-only."
  value = {
    subscription_id    = local.foundation.subscription_id
    tenant_id          = local.foundation.tenant_id
    resource_group_id  = local.foundation.resource_group_id
    foundry_account_id = local.foundation.foundry_account_id
    outbound_subnet_id = local.foundation.outbound_subnet_id
    inbound_subnet_id  = local.foundation.inbound_subnet_id
  }
}
