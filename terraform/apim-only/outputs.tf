output "resource_group_name" {
  description = "Resource group containing the isolated architecture."
  value       = azurerm_resource_group.main.name
}

output "foundry_account_id" {
  description = "ARM ID of the Microsoft Foundry account."
  value       = azapi_resource.foundry.id
}

output "model_deployments" {
  description = "Existing Foundry deployment names published through the model-scoped APIs."
  value       = [for model in local.models : model.deployment_name]
}

output "apim_gateway_url" {
  description = "Public HTTPS URL of the Standard v2 API Management instance."
  value       = "https://${local.apim_name}.azure-api.net"
}

output "apim_portal_url" {
  description = "Azure portal resource page for the Standard v2 instance."
  value       = "https://portal.azure.com/#resource${azapi_resource.apim.id}/overview"
}

output "apim_model_base_urls" {
  description = "OpenAI-compatible base URL for each model-scoped API."
  value       = local.apim_model_base_urls
}

output "apim_model_endpoints" {
  description = "Chat-completion endpoint for each model-scoped API."
  value = {
    for deployment, base_url in local.apim_model_base_urls :
    deployment => "${base_url}/chat/completions"
  }
}

output "apim_subscription_keys" {
  description = "Primary API-scoped subscription keys; send as Ocp-Apim-Subscription-Key."
  value = {
    for model_id, model in local.models :
    model.deployment_name => azurerm_api_management_subscription.model[model_id].primary_key
  }
  sensitive = true
}

output "apim_entra_model_endpoints" {
  description = "Token-only chat endpoints; existing subscription-key URLs are unchanged."
  value = {
    for deployment, base_url in local.entra_model_base_urls :
    deployment => "${base_url}/chat/completions"
  }
}

output "apim_entra_authentication" {
  description = "Nonsecret Entra API identifiers, scope, and required per-model roles."
  value = {
    tenant_id                   = var.tenant_id
    client_id                   = azuread_application.model_access.client_id
    resource_uri                = local.entra_resource_uri
    delegated_scope             = "${local.entra_resource_uri}/access_as_user"
    service_principal_object_id = azuread_service_principal.model_access.object_id
    model_roles = {
      for model_id, model in local.models :
      model.deployment_name => local.entra_model_roles[model_id]
    }
  }
}

output "apim_subscription_ids" {
  description = "Standalone API-scoped subscription ARM IDs, one per model."
  value = {
    for model_id, model in local.models :
    model.deployment_name => azurerm_api_management_subscription.model[model_id].id
  }
}

output "apim_model_backend_ids" {
  description = "Three model backend references to the existing private Foundry account."
  value = {
    for model_id, model in local.models :
    model.deployment_name => azapi_resource.model_backend[model_id].id
  }
}

output "apim_model_product_ids" {
  description = "ARM IDs of the three published, model-specific APIM products."
  value = {
    for model_id, model in local.models :
    model.deployment_name => azurerm_api_management_product.model[model_id].id
  }
}

output "shared_vnet_id" {
  description = "Shared virtual network for AI Gateway and Foundry."
  value       = azurerm_virtual_network.shared.id
}

output "subnet_ids" {
  description = "Four shared-VNet subnets: separate inbound and outbound networking for Foundry and AI Gateway."
  value = {
    foundry_inbound     = azurerm_subnet.foundry_inbound.id
    foundry_outbound    = azurerm_subnet.foundry_outbound.id
    ai_gateway_outbound = azurerm_subnet.ai_gateway_outbound.id
    ai_gateway_inbound  = azurerm_subnet.ai_gateway_inbound.id
  }
}
