output "foundry_account_id" {
  description = "ARM ID of the private Microsoft Foundry account."
  value       = azapi_resource.foundry.id
}

output "project_id" {
  description = "ARM ID of the recreated Foundry project."
  value       = azapi_resource.project.id
}

output "pending_models" {
  description = "Requested models not included in this apply, with the reason they are staged."
  value       = var.enable_deepseek ? {} : { "FW-DeepSeek-V4.1-Flash" = "Waiting for existing quota to be released." }
}

output "gateway_foundation" {
  description = "Nonsecret connection metadata for the separate AI Gateway root."
  value = {
    subscription_id     = var.subscription_id
    tenant_id           = var.tenant_id
    resource_group_id   = data.azurerm_resource_group.main.id
    resource_group_name = data.azurerm_resource_group.main.name
    location            = data.azurerm_resource_group.main.location
    tags                = data.azurerm_resource_group.main.tags
    name_suffix         = random_string.suffix.result
    foundry_account_id  = azapi_resource.foundry.id
    foundry_name        = local.foundry_name
    outbound_subnet_id  = azurerm_subnet.ai_gateway_outbound.id
    models = merge(
      { for key, model in local.azurerm_models : key => merge(model, { deployment_id = azurerm_cognitive_deployment.model[key].id }) },
      { model_router = merge(local.models.model_router, { deployment_id = azapi_resource.model_router.id }) },
      { for key, model in local.anthropic_models : key => merge(model, { deployment_id = azapi_resource.anthropic[key].id }) }
    )
  }
}
