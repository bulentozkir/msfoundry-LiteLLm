output "resource_group_name" {
  description = "Resource group containing the isolated architecture."
  value       = azurerm_resource_group.main.name
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
  value       = azapi_resource.foundry.id
}

output "model_deployments" {
  description = "Client-facing deployment names routed through AI Gateway."
  value       = [for model in local.models : model.deployment_name]
}

output "model_access_keys" {
  description = "Three separate runtime keys, named by intended model. AIGateway preview keys are gateway-scoped, not model-isolated."
  value = {
    for model_id, model in local.models :
    model.deployment_name => azapi_resource_action.runtime_api_key_secrets[model_id].sensitive_output.primaryKey
  }
  sensitive = true
}

output "runtime_key_scope" {
  description = "Authorization scope of every runtime key in the AI Gateway preview tier."
  value       = "gateway: every key can access all published models; per-model subscriptions are not supported"
}

output "shared_vnet_id" {
  description = "Shared virtual network for AI Gateway and Foundry."
  value       = azurerm_virtual_network.shared.id
}

output "subnet_ids" {
  description = "Foundry inbound/outbound and AI Gateway outbound subnets. Public gateway ingress needs no private-endpoint subnet."
  value = {
    foundry_inbound     = azurerm_subnet.foundry_inbound.id
    foundry_outbound    = azurerm_subnet.foundry_outbound.id
    ai_gateway_outbound = azurerm_subnet.ai_gateway_outbound.id
  }
}
