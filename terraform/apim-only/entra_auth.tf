data "azuread_client_config" "current" {}

locals {
  entra_resource_uri = "api://${var.tenant_id}/${local.apim_name}"
  entra_role_values = {
    gpt5_4_mini = "Model.Gpt.Invoke"
    phi         = "Model.Phi.Invoke"
    deepseek    = "Model.DeepSeek.Invoke"
  }
  entra_scope_id = uuidv5("url", "${local.entra_resource_uri}/access_as_user")
  entra_model_roles = {
    for model_id, model in local.models : model_id => {
      id    = uuidv5("url", "${local.entra_resource_uri}/${local.entra_role_values[model_id]}")
      value = local.entra_role_values[model_id]
    }
  }
  entra_model_assignments = merge([
    for model_id, principal_ids in var.entra_model_principal_ids : {
      for principal_id in principal_ids : "${model_id}/${lower(principal_id)}" => {
        model_id     = model_id
        principal_id = principal_id
      }
    }
  ]...)
  entra_model_base_urls = {
    for model_id, model in local.models :
    model.deployment_name => "https://${local.apim_name}.azure-api.net/entra/${model.resource_name}/openai/v1"
  }
}

resource "azuread_application" "model_access" {
  display_name     = "${local.apim_name}-model-access"
  identifier_uris  = [local.entra_resource_uri]
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = local.entra_scope_id
      value                      = "access_as_user"
      type                       = "Admin"
      enabled                    = true
      admin_consent_display_name = "Access model APIs as the signed-in user"
      admin_consent_description  = "Call the gateway as the signed-in user, subject to separately assigned model roles."
    }
  }

  dynamic "app_role" {
    for_each = local.entra_model_roles
    content {
      id                   = app_role.value.id
      value                = app_role.value.value
      display_name         = "Invoke ${local.models[app_role.key].deployment_name}"
      description          = "Invoke only ${local.models[app_role.key].deployment_name} through its Entra-protected APIM API."
      allowed_member_types = ["User", "Application"]
      enabled              = true
    }
  }
}

resource "azuread_service_principal" "model_access" {
  client_id                    = azuread_application.model_access.client_id
  owners                       = [data.azuread_client_config.current.object_id]
  app_role_assignment_required = true
}

resource "azuread_application_pre_authorized" "azure_cli" {
  application_id       = azuread_application.model_access.id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
  permission_ids       = [local.entra_scope_id]
}

resource "azuread_app_role_assignment" "model" {
  for_each = local.entra_model_assignments

  app_role_id         = local.entra_model_roles[each.value.model_id].id
  principal_object_id = each.value.principal_id
  resource_object_id  = azuread_service_principal.model_access.object_id
}

resource "azurerm_api_management_api" "entra_model" {
  for_each = local.models

  name                  = "${each.value.resource_name}-entra"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azapi_resource.apim.name
  revision              = "1"
  display_name          = "${each.value.deployment_name} (Entra ID)"
  path                  = "entra/${each.value.resource_name}/openai/v1"
  protocols             = ["https"]
  subscription_required = false
  service_url           = ""

  # No default upstream: the API cannot reach Foundry before its protected policy is attached.
  import {
    content_format = "openapi+json"
    content_value = jsonencode(merge(
      jsondecode(azurerm_api_management_api.model[each.key].import[0].content_value),
      {
        info = {
          title   = "${each.value.deployment_name} (Entra ID)"
          version = "1.0"
        }
      }
    ))
  }
}

resource "azurerm_api_management_api_policy" "entra_model" {
  for_each = local.models

  api_name            = azurerm_api_management_api.entra_model[each.key].name
  api_management_name = azapi_resource.apim.name
  resource_group_name = azurerm_resource_group.main.name
  xml_content = templatefile("${path.module}/templates/model-policy.xml.tftpl", {
    deployment_name = each.value.deployment_name
    backend_name    = azapi_resource.model_backend[each.key].name
    format          = each.value.format
    tenant_id       = var.tenant_id
    entra_client_id = azuread_application.model_access.client_id
    entra_role      = local.entra_model_roles[each.key].value
  })

  depends_on = [time_sleep.wait_for_apim_foundry_rbac]
}

resource "azurerm_api_management_api_tag" "entra_model" {
  for_each = local.models

  api_id = trimsuffix(azurerm_api_management_api.entra_model[each.key].id, ";rev=${azurerm_api_management_api.entra_model[each.key].revision}")
  name   = azurerm_api_management_tag.ai_model.name

  depends_on = [azurerm_api_management_api_policy.entra_model]
}
