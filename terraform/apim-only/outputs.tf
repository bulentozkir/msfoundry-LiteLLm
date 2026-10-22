output "resource_group_name" {
  description = "Resource group containing the isolated architecture."
  value       = azurerm_resource_group.main.name
}

output "foundry_account_id" {
  description = "ARM ID of the Microsoft Foundry account."
  value       = azapi_resource.foundry.id
}

output "model_deployments" {
  description = "All retained Foundry deployments. The additional models are published by the AI Gateway root, not the legacy Standard APIs."
  value       = [for model in merge(local.models, local.additional_models) : model.deployment_name]
}

output "apim_gateway_url" {
  description = "Public HTTPS URL of the Standard v2 API Management instance."
  value       = var.standard_gateway_enabled ? "https://${local.apim_name}.azure-api.net" : null
}

output "apim_portal_url" {
  description = "Azure portal resource page for the Standard v2 instance."
  value       = var.standard_gateway_enabled ? "https://portal.azure.com/#resource${azapi_resource.apim[0].id}/overview" : null
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
    for model_id, model in local.standard_models :
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
    for model_id, model in local.standard_models :
    model.deployment_name => azurerm_api_management_subscription.model[model_id].id
  }
}

output "apim_model_backend_ids" {
  description = "Three model backend references to the existing private Foundry account."
  value = {
    for model_id, model in local.standard_models :
    model.deployment_name => azapi_resource.model_backend[model_id].id
  }
}

output "apim_model_product_ids" {
  description = "ARM IDs of the three published, model-specific APIM products."
  value = {
    for model_id, model in local.standard_models :
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

output "gateway_foundation" {
  description = "Nonsecret connection metadata for the separate AI Gateway root. This root remains the sole owner of Foundry and shared networking."
  value = {
    subscription_id          = var.subscription_id
    tenant_id                = var.tenant_id
    resource_group_id        = azurerm_resource_group.main.id
    resource_group_name      = azurerm_resource_group.main.name
    location                 = azurerm_resource_group.main.location
    tags                     = var.tags
    name_suffix              = random_string.suffix.result
    publisher_name           = var.publisher_name
    publisher_email          = var.publisher_email
    standard_gateway_enabled = var.standard_gateway_enabled
    foundry_account_id       = azapi_resource.foundry.id
    foundry_name             = local.foundry_name
    outbound_subnet_id       = azurerm_subnet.ai_gateway_outbound.id
    inbound_subnet_id        = azurerm_subnet.ai_gateway_inbound.id
    private_dns_zone_id      = azurerm_private_dns_zone.ai_gateway.id
    models = merge(
      {
        for model_id, model in local.models :
        model_id => merge(model, {
          deployment_id = azurerm_cognitive_deployment.model[model_id].id
        })
      },
      {
        for model_id, model in local.additional_models :
        model_id => merge(model, {
          deployment_id = model.format == "Anthropic" ? azapi_resource.claude_opus_5_5.id : azurerm_cognitive_deployment.additional[model_id].id
        })
      },
    )
  }
}
