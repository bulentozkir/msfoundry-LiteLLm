# ---------------------------------------------------------------------------
# APIM Developer for chat3 -> Foundry routing.
# ---------------------------------------------------------------------------

resource "azurerm_api_management" "chat3" {
  name                = "apim-chat3-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "Developer_1"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_api_management_api" "chat3_foundry" {
  name                  = "chat3-foundry"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.chat3.name
  revision              = "1"
  display_name          = "Chat3 Foundry Proxy"
  path                  = "chat3"
  protocols             = ["https"]
  subscription_required = false
  service_url           = trimsuffix(var.azure_openai_endpoint, "/")
}

resource "azurerm_api_management_api_operation" "chat3_completions" {
  operation_id        = "chat-completions"
  api_name            = azurerm_api_management_api.chat3_foundry.name
  api_management_name = azurerm_api_management.chat3.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Chat Completions"
  method              = "POST"
  url_template        = "/chat/completions"

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_operation_policy" "chat3_completions" {
  api_name            = azurerm_api_management_api.chat3_foundry.name
  api_management_name = azurerm_api_management.chat3.name
  resource_group_name = azurerm_resource_group.main.name
  operation_id        = azurerm_api_management_api_operation.chat3_completions.operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <set-variable name="requestedModel" value='@{
      var body = context.Request.Body.As<Newtonsoft.Json.Linq.JObject>(preserveContent: true);
      return (string)(body?["model"] ?? "");
    }' />
    <choose>
      <when condition='@(context.Variables.GetValueOrDefault<string>("requestedModel").Equals("${var.phi_model_alias}", System.StringComparison.OrdinalIgnoreCase))'>
        <set-backend-service base-url="${local.foundry_model_inference_endpoint}" />
        <rewrite-uri template="/chat/completions?api-version=${var.apim_phi_api_version}" />
        <set-body>@{
          var body = context.Request.Body.As<Newtonsoft.Json.Linq.JObject>(preserveContent: true) ?? new Newtonsoft.Json.Linq.JObject();
          body["model"] = "${azurerm_cognitive_deployment.phi.name}";
          return body.ToString(Newtonsoft.Json.Formatting.None);
        }</set-body>
      </when>
      <otherwise>
        <set-backend-service base-url="${trimsuffix(var.azure_openai_endpoint, "/")}" />
        <rewrite-uri template="/openai/deployments/${var.azure_openai_deployment_name}/chat/completions?api-version=${var.azure_openai_api_version}" />
        <set-body>@{
          var body = context.Request.Body.As<Newtonsoft.Json.Linq.JObject>(preserveContent: true) ?? new Newtonsoft.Json.Linq.JObject();
          body["model"] = "${var.azure_openai_deployment_name}";
          return body.ToString(Newtonsoft.Json.Formatting.None);
        }</set-body>
      </otherwise>
    </choose>
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="foundryToken" ignore-error="false" />
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["foundryToken"])</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

resource "azurerm_role_assignment" "apim_foundry_openai_user" {
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.chat3.identity[0].principal_id
}

resource "azurerm_role_assignment" "apim_foundry_inference_user" {
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.chat3.identity[0].principal_id
}
