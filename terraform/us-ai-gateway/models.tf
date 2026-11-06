data "azapi_resource" "deployment" {
  for_each = local.foundation.models

  type                   = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  resource_id            = each.value.deployment_id
  response_export_values = ["properties.capabilities"]
}

locals {
  models = {
    for key, model in local.foundation.models : key => merge(model, {
      resource_name = trim(replace(replace(lower(model.deployment_name), "/[^a-z0-9-]+/", "-"), "/-+/", "-"), "-")
    })
  }

  capability_endpoints = [
    { capability = "chatCompletion", endpoint = "/openai/v1/chat/completions" },
    { capability = "responses", endpoint = "/openai/v1/responses" },
    { capability = "completion", endpoint = "/openai/v1/completions" },
    { capability = "embeddings", endpoint = "/openai/v1/embeddings" },
    { capability = "imageGenerations", endpoint = "/openai/v1/images/generations" },
  ]

  model_capabilities = {
    for key in keys(local.models) :
    key => try(tomap(data.azapi_resource.deployment[key].output.properties.capabilities), tomap({}))
  }

  discovered_endpoints = {
    for key in keys(local.models) : key => [
      for mapping in local.capability_endpoints : mapping.endpoint
      if try(lower(trimspace(tostring(local.model_capabilities[key][mapping.capability]))) == "true", false)
    ]
  }

  model_endpoints = {
    for key, model in local.models : key => try(
      var.model_endpoint_overrides[key],
      lower(model.format) == "anthropic" ? ["/anthropic/v1/messages"] :
      length(local.discovered_endpoints[key]) > 0 ? local.discovered_endpoints[key] :
      anytrue([for capability in values(local.model_capabilities[key]) : try(lower(trimspace(tostring(capability))) == "true", false)]) ? [] :
      ["/openai/v1/chat/completions"]
    )
  }
}

resource "azapi_resource" "gateway_model" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/aigateways/workspaces/modelProviders/models@${local.management_api}"
  name      = each.value.resource_name
  parent_id = azapi_resource.foundry_provider.id

  body = {
    properties = merge(
      {
        displayName        = each.value.deployment_name
        supportedEndpoints = local.model_endpoints[each.key]
        deployment = {
          resourceId   = each.value.deployment_id
          modelName    = each.value.deployment_name
          modelVersion = each.value.version
        }
      },
      lower(each.value.format) == "openai" ? { apiFormat = "OpenAIChatCompletions" } :
      lower(each.value.format) == "anthropic" ? { apiFormat = "AnthropicMessages" } : {}
    )
  }

  schema_validation_enabled = false

  lifecycle {
    precondition {
      condition     = length(local.model_endpoints[each.key]) > 0
      error_message = "This deployment advertises capabilities without a supported gateway endpoint. Review it and set a model_endpoint_overrides entry if appropriate."
    }
  }
}

resource "azapi_resource" "model_alias" {
  for_each = local.models

  type      = "Microsoft.ApiManagement/aigateways/workspaces/aliases@${local.management_api}"
  name      = each.value.resource_name
  parent_id = local.workspace_id

  body = {
    properties = {
      aliasName = each.value.deployment_name
      backendModels = [{
        resourceId = azapi_resource.gateway_model[each.key].id
      }]
    }
  }

  schema_validation_enabled = false
}
