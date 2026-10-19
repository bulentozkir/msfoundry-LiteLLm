mock_provider "azurerm" {}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "22222222-2222-4222-8222-222222222222"
    }
  }
}

mock_provider "azapi" {}

mock_provider "random" {
  mock_resource "random_string" {
    override_during = plan
    defaults = {
      result = "test01"
    }
  }
}

mock_provider "time" {}

override_resource {
  target          = azapi_resource.foundry
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-test01"
  }
}

override_resource {
  target          = azurerm_api_management_api.model["gpt5_4_mini"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-foundry-test01/apis/gpt5-4mini;rev=1"
  }
}

override_resource {
  target          = azurerm_api_management_api.model["phi"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-foundry-test01/apis/phi;rev=1"
  }
}

override_resource {
  target          = azurerm_api_management_api.model["deepseek"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-foundry-test01/apis/fw-deepseek-v4-1-flash;rev=1"
  }
}

run "standard_v2_model_subscriptions" {
  command = plan

  assert {
    condition = (
      azapi_resource.apim.body.sku.name == "StandardV2" &&
      azapi_resource.apim.body.sku.capacity == 1 &&
      azapi_resource.apim.body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.apim.body.properties.virtualNetworkType == "External" &&
      azapi_resource.apim.identity[0].type == "SystemAssigned"
    )
    error_message = "Use Standard v2 with one unit, public ingress, outbound VNet integration, and managed identity."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      endswith(azurerm_api_management_api.model[model_id].id, ";rev=1") &&
      endswith(azurerm_api_management_subscription.model[model_id].api_id, "/apis/${model.resource_name}") &&
      !strcontains(azurerm_api_management_subscription.model[model_id].api_id, ";rev=")
    ])
    error_message = "Scope each subscription to its own current API without the AzureRM revision suffix."
  }

  assert {
    condition = (
      azurerm_api_management_tag.ai_model.name == "aimodel" &&
      alltrue([
        for model_id in keys(local.models) :
        azurerm_api_management_api_tag.model[model_id].name == "aimodel" &&
        azurerm_api_management_api_tag.model[model_id].api_id == azurerm_api_management_subscription.model[model_id].api_id
      ])
    )
    error_message = "Register the same three protected APIs in the portal's AI Models view without creating duplicate APIs."
  }

  assert {
    condition = (
      length(azurerm_api_management_api.model) == 3 &&
      length(azapi_resource.model_backend) == 3 &&
      length(azurerm_api_management_api_tag.model) == 3 &&
      length(azurerm_api_management_api_policy.model) == 3 &&
      length(azurerm_api_management_subscription.model) == 3 &&
      alltrue([
        for api in azurerm_api_management_api.model :
        api.subscription_required && api.protocols == toset(["https"])
      ]) &&
      alltrue([
        for subscription in azurerm_api_management_subscription.model :
        subscription.state == "active" && !subscription.allow_tracing && subscription.product_id == null
      ])
    )
    error_message = "Publish exactly three HTTPS-only, subscription-required APIs with active API-scoped subscriptions."
  }

  assert {
    condition = (
      length(azurerm_api_management_product.model) == 3 &&
      length(azurerm_api_management_product_api.model) == 3 &&
      length(azurerm_api_management_product_group.model) == 3 &&
      alltrue([
        for model_id, model in local.models :
        azurerm_api_management_product.model[model_id].product_id == model.resource_name &&
        azurerm_api_management_product.model[model_id].subscription_required &&
        azurerm_api_management_product.model[model_id].approval_required &&
        azurerm_api_management_product.model[model_id].subscriptions_limit == 1 &&
        azurerm_api_management_product.model[model_id].published &&
        azurerm_api_management_product_api.model[model_id].product_id == azurerm_api_management_product.model[model_id].product_id &&
        azurerm_api_management_product_api.model[model_id].api_name == azurerm_api_management_api.model[model_id].name &&
        azurerm_api_management_product_group.model[model_id].product_id == azurerm_api_management_product.model[model_id].product_id &&
        azurerm_api_management_product_group.model[model_id].group_name == "developers"
      ])
    )
    error_message = "Publish one protected product per model, link only its matching API, and require approval with one subscription per signed-in developer per product."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      length(jsondecode(azurerm_api_management_api.model[model_id].import[0].content_value).paths) == 2 &&
      jsondecode(azurerm_api_management_api.model[model_id].import[0].content_value).paths["/chat/completions"].post.operationId == "chat-completions" &&
      jsondecode(azurerm_api_management_api.model[model_id].import[0].content_value).paths["/deployments/${model.deployment_name}/chat/completions"].post.operationId == "deployment-chat-completions"
    ])
    error_message = "Preserve the canonical chat route and expose only the same model's exact deployment-qualified Azure Portal route."
  }

  assert {
    condition = alltrue([
      for policy in azurerm_api_management_api_policy.model :
      length(regexall("<inbound>\\s*<cors allow-credentials=\"false\">", policy.xml_content)) == 1 &&
      length(regexall("<origin>", policy.xml_content)) == 3 &&
      strcontains(policy.xml_content, "<origin>https://ms.portal.azure.com</origin>") &&
      strcontains(policy.xml_content, "<origin>https://portal.azure.com</origin>") &&
      strcontains(policy.xml_content, "System.Text.RegularExpressions.Regex.IsMatch(origin, @\"\\Ahttps://sandbox-[0-9]+\\.reactblade(-ms)?\\.portal\\.azure\\.net\\z\")") &&
      strcontains(policy.xml_content, "? origin : \"https://ms.portal.azure.com\";") &&
      !strcontains(policy.xml_content, "<origin>*</origin>") &&
      length(regexall("<method>", policy.xml_content)) == 1 &&
      strcontains(policy.xml_content, "<method>POST</method>") &&
      strcontains(policy.xml_content, "<allowed-headers>")
    ])
    error_message = "Handle browser preflight before inherited policies, allowing POST only from Azure Portal and its strictly matched HTTPS sandbox origins without wildcard origins or browser credentials."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      jsondecode(azurerm_api_management_api.model[model_id].import[0].content_value).components.schemas.ChatCompletionRequest.properties.model.enum == [model.deployment_name] &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "body[\"model\"] = \"${model.deployment_name}\";") &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "validate-as=\"json\" action=\"prevent\"") &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "copy-unmatched-params=\"false\"") &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "name=\"api-key\" exists-action=\"delete\"") &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "<set-backend-service id=\"apim-generated-policy\" backend-id=\"${model.resource_name}\" />") &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "authentication-managed-identity resource=\"https://cognitiveservices.azure.com/\" ignore-error=\"false\"") &&
      strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "buffer-response=\"false\"")
    ])
    error_message = "Validate JSON and model selection, pin the deployment, expose the portal-managed backend reference, use managed identity, and preserve streaming."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      azapi_resource.model_backend[model_id].body.properties.url == azurerm_api_management_api.model[model_id].service_url &&
      azapi_resource.model_backend[model_id].body.properties.url == "https://${local.foundry_name}.services.ai.azure.com/${model.format == "OpenAI" ? "openai/v1" : "models"}" &&
      azapi_resource.model_backend[model_id].body.properties.protocol == "http" &&
      azapi_resource.model_backend[model_id].body.properties.resourceId == "https://management.azure.com${azapi_resource.foundry.id}"
    ])
    error_message = "Link each API to its own HTTPS Foundry backend with the correct OpenAI v1 or model-inference base URL and Foundry resource association."
  }

  assert {
    condition = (
      azurerm_role_assignment.apim_foundry_user.principal_type == "ServicePrincipal" &&
      endswith(azurerm_role_assignment.apim_foundry_user.role_definition_id, "/53ca6127-db72-4b80-b1b0-d745d6d5456d") &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      alltrue([
        for backend in azapi_resource.model_backend :
        backend.body.properties.credentials.managedIdentity.resource == "https://cognitiveservices.azure.com/"
      ])
    )
    error_message = "Grant the APIM managed identity Foundry User access without enabling Foundry API-key authentication."
  }

  assert {
    condition = (
      contains(azurerm_subnet.ai_gateway_outbound.address_prefixes, "10.42.2.0/24") &&
      azurerm_subnet.ai_gateway_outbound.delegation[0].service_delegation[0].name == "Microsoft.Web/serverFarms" &&
      contains(azurerm_network_security_rule.foundry_private_https.source_address_prefixes, "10.42.2.0/24") &&
      contains(azurerm_private_endpoint.apim.private_service_connection[0].subresource_names, "Gateway") &&
      azapi_resource.foundry.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.foundry.body.properties.disableLocalAuth &&
      length(azurerm_cognitive_deployment.model) == 3
    )
    error_message = "Reuse the original delegated outbound subnet while retaining private Foundry, its three deployments, and an inbound gateway private endpoint."
  }
}
