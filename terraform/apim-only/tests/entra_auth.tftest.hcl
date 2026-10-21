variables {
  standard_gateway_enabled = true
}

mock_provider "azurerm" {}
mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = { value = [] }
    }
  }
}
mock_provider "time" {}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "22222222-2222-4222-8222-222222222222"
    }
  }

  mock_resource "azuread_application" {
    override_during = plan
    defaults = {
      client_id = "11111111-1111-4111-8111-111111111111"
      id        = "/applications/33333333-3333-4333-8333-333333333333"
    }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    override_during = plan
    defaults = {
      result = "test01"
    }
  }
}

run "isolated_entra_model_access" {
  command = plan

  variables {
    entra_model_principal_ids = {
      gpt5_4_mini = ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]
      phi         = ["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"]
    }
  }

  assert {
    condition = (
      azuread_application.model_access.sign_in_audience == "AzureADMyOrg" &&
      one(azuread_application.model_access.api).requested_access_token_version == 2 &&
      length(azuread_application.model_access.app_role) == 3 &&
      alltrue([
        for role in azuread_application.model_access.app_role :
        role.enabled && role.allowed_member_types == toset(["User", "Application"])
      ]) &&
      azuread_service_principal.model_access.app_role_assignment_required
    )
    error_message = "Use single-tenant v2 access tokens and three explicitly assigned user/application model roles."
  }

  assert {
    condition = (
      length(azuread_app_role_assignment.model) == 2 &&
      azuread_app_role_assignment.model["gpt5_4_mini/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"].app_role_id == local.entra_model_roles.gpt5_4_mini.id &&
      azuread_app_role_assignment.model["phi/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"].app_role_id == local.entra_model_roles.phi.id &&
      !contains(keys(local.entra_model_assignments), "deepseek/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    )
    error_message = "Assign only explicitly configured principals to their selected models; do not grant access to omitted models."
  }

  assert {
    condition = (
      azuread_application_pre_authorized.azure_cli.authorized_client_id == "04b07795-8ddb-461a-bbee-02f9e1bf7b46" &&
      azuread_application_pre_authorized.azure_cli.permission_ids == toset([local.entra_scope_id]) &&
      length(azurerm_cognitive_deployment.model) == 3 &&
      length(azapi_resource.model_backend) == 3 &&
      length(azurerm_api_management_subscription.model) == 3
    )
    error_message = "Preauthorize only the delegated CLI scope, without creating extra models, backends, subscriptions, or client credentials."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      azurerm_api_management_api.model[model_id].subscription_required &&
      azurerm_api_management_api.model[model_id].path == "${model.resource_name}/openai/v1" &&
      !azurerm_api_management_api.entra_model[model_id].subscription_required &&
      azurerm_api_management_api.entra_model[model_id].path == "entra/${model.resource_name}/openai/v1" &&
      azurerm_api_management_api.entra_model[model_id].protocols == toset(["https"]) &&
      azurerm_api_management_api.entra_model[model_id].service_url == "" &&
      azurerm_api_management_api_tag.entra_model[model_id].name == "aimodel"
    ])
    error_message = "Keep key APIs unchanged and expose separate HTTPS Entra APIs with no unprotected default upstream."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      jsondecode(azurerm_api_management_api.entra_model[model_id].import[0].content_value).paths == jsondecode(azurerm_api_management_api.model[model_id].import[0].content_value).paths &&
      jsondecode(azurerm_api_management_api.entra_model[model_id].import[0].content_value).components == jsondecode(azurerm_api_management_api.model[model_id].import[0].content_value).components &&
      !strcontains(azurerm_api_management_api_policy.model[model_id].xml_content, "validate-azure-ad-token") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "tenant-id=\"${var.tenant_id}\"") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "<audience>11111111-1111-4111-8111-111111111111</audience>") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "!token.Claims.ContainsKey(&quot;roles&quot;)") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "!token.Claims[&quot;roles&quot;].Contains(&quot;${local.entra_model_roles[model_id].value}&quot;)") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "<set-status code=\"403\" reason=\"Forbidden\" />")
    ])
    error_message = "Validate gateway-audience tokens at API scope and reject missing/wrong model roles while preserving the exact model request contract."
  }

  assert {
    condition = alltrue([
      for model_id, model in local.models :
      length(regexall("<inbound>\\s*<cors allow-credentials=\"false\">", azurerm_api_management_api_policy.entra_model[model_id].xml_content)) == 1 &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "name=\"Authorization\" exists-action=\"delete\"") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "body[\"model\"] = \"${model.deployment_name}\";") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "validate-as=\"json\" action=\"prevent\"") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "copy-unmatched-params=\"false\"") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "backend-id=\"${model.resource_name}\"") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "authentication-managed-identity resource=\"https://cognitiveservices.azure.com/\" ignore-error=\"false\"") &&
      strcontains(azurerm_api_management_api_policy.entra_model[model_id].xml_content, "buffer-response=\"false\"")
    ])
    error_message = "Preserve CORS, schema validation, fixed routing, backend MI, caller-token removal, and streaming on every Entra API."
  }
}

run "no_implicit_entra_access" {
  command = plan

  variables {
    entra_model_principal_ids = {}
  }

  assert {
    condition     = length(azuread_app_role_assignment.model) == 0
    error_message = "An empty assignment map must not grant anyone model access."
  }
}

run "reject_unknown_model_assignment" {
  command = plan

  variables {
    entra_model_principal_ids = {
      all_models = ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]
    }
  }

  expect_failures = [var.entra_model_principal_ids]
}

run "reject_invalid_principal_assignment" {
  command = plan

  variables {
    entra_model_principal_ids = {
      phi = ["not-an-object-id"]
    }
  }

  expect_failures = [var.entra_model_principal_ids]
}
