locals {
  gateway_hostname = try(azapi_resource.gateway.output.properties.frontend.defaultHostname, null)
  gateway_url      = local.gateway_hostname == null || local.gateway_hostname == "" ? null : "https://${local.gateway_hostname}"
}

output "gateway_id" {
  description = "ARM ID of the dedicated Microsoft.ApiManagement/aigateways resource."
  value       = azapi_resource.gateway.id
}

output "gateway_url" {
  description = "Public HTTPS frontend URL read from the gateway response, not constructed from its resource name."
  value       = local.gateway_url
}

output "gateway_sku" {
  description = "SKU reported by the gateway service."
  value       = try(azapi_resource.gateway.output.sku.name, null)
}

output "gateway_principal_id" {
  description = "System-assigned identity granted Foundry User on the private account."
  value       = azapi_resource.gateway.identity[0].principal_id
}

output "runtime_key_resource_id" {
  description = "Nonsecret ARM ID of the gateway-wide runtime key. Terraform does not retrieve the key value."
  value       = azapi_resource.runtime_key.id
}

output "model_routes" {
  description = "Registered foundation deployment names, preserved aliases, and native endpoint paths."
  value = {
    for key, model in local.models : key => {
      deployment_name = model.deployment_name
      deployment_id   = model.deployment_id
      alias           = model.deployment_name
      endpoint_paths  = local.model_endpoints[key]
    }
  }
}

output "model_endpoint_urls" {
  description = "Runtime operation URLs keyed by foundation model key; null until Azure returns the frontend hostname."
  value = local.gateway_url == null ? null : {
    for key, paths in local.model_endpoints :
    key => [for path in paths : "${local.gateway_url}/default/models${path}"]
  }
}
