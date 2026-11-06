mock_provider "azurerm" {}
mock_provider "time" {}

mock_provider "azapi" {
  mock_data "azapi_resource" {
    override_during = plan
    defaults = {
      output = {
        location = "eastus2"
        properties = {
          endpoint            = "https://fdry-test01.services.ai.azure.com/"
          disableLocalAuth    = true
          publicNetworkAccess = "Disabled"
          delegations = [{
            properties = { serviceName = "Microsoft.App/environments" }
          }]
          capabilities = { chatCompletion = "true" }
        }
      }
    }
  }

  mock_resource "azapi_resource" {
    override_during = plan
    defaults = {
      identity = {
        principal_id = "22222222-2222-4222-8222-222222222222"
        tenant_id    = "11111111-1111-4111-8111-111111111111"
      }
      output = {
        sku = { name = "Premium" }
        properties = {
          frontend = { defaultHostname = "returned-by-arm.eastus2-01.ai.gateway.azure.com" }
        }
      }
    }
  }
}

override_resource {
  target          = azapi_resource.gateway
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/aigateways/aigw-us-test01"
    identity = {
      principal_id = "22222222-2222-4222-8222-222222222222"
      tenant_id    = "11111111-1111-4111-8111-111111111111"
    }
    output = {
      sku = { name = "Premium" }
      properties = {
        frontend = { defaultHostname = "returned-by-arm.eastus2-01.ai.gateway.azure.com" }
      }
    }
  }
}

override_resource {
  target          = azapi_resource.foundry_provider
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/aigateways/aigw-us-test01/workspaces/default/modelProviders/fdry-test01"
  }
}

override_data {
  target = data.terraform_remote_state.foundation
  values = {
    outputs = {
      gateway_foundation = {
        subscription_id     = "00000000-0000-0000-0000-000000000000"
        tenant_id           = "11111111-1111-4111-8111-111111111111"
        resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
        resource_group_name = "rg-test"
        location            = "eastus2"
        tags                = { environment = "test" }
        name_suffix         = "test01"
        foundry_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
        foundry_name        = "fdry-test01"
        outbound_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/gateway-outbound"
        models = {
          model_router = {
            deployment_name = "model-router"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/model-router"
            format          = "OpenAI"
            catalog_name    = "model-router"
            version         = "2025-11-18"
          }
          gpt6_astra = {
            deployment_name = "gpt-6-astra"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/gpt-6-astra"
            format          = "OpenAI"
            catalog_name    = "gpt-6-astra"
            version         = "2026-09-03"
          }
          kimi_k3 = {
            deployment_name = "FW-Kimi-K3"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/FW-Kimi-K3"
            format          = "Fireworks"
            catalog_name    = "FW-Kimi-K3"
            version         = "1"
          }
          claude_opus_5_5 = {
            deployment_name = "claude-opus-5-5"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/claude-opus-5-5"
            format          = "Anthropic"
            catalog_name    = "claude-opus-5-5"
            version         = "2"
          }
          claude_opus_5_5_fast = {
            deployment_name = "claude-opus-5-5-fast"
            deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/claude-opus-5-5-fast"
            format          = "Anthropic"
            catalog_name    = "claude-opus-5-5-fast"
            version         = "2"
          }
        }
      }
    }
  }
}

run "dedicated_gateway_private_foundry_and_rbac" {
  command = plan

  assert {
    condition = (
      data.terraform_remote_state.foundation.config.path == abspath("${path.module}\\..\\us-foundation\\terraform.tfstate") &&
      azapi_resource.gateway.type == "Microsoft.ApiManagement/aigateways@2025-09-01-preview" &&
      azapi_resource.gateway.name == "aigw-us-test01" &&
      azapi_resource.gateway.location == "eastus2" &&
      azapi_resource.gateway.identity[0].type == "SystemAssigned" &&
      azapi_resource.gateway.body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.gateway.body.properties.backend.subnet.id == local.foundation.outbound_subnet_id &&
      azapi_resource.gateway.replace_triggers_external_values.backend_subnet_id == lower(local.foundation.outbound_subnet_id) &&
      !can(azapi_resource.gateway.body.sku) &&
      output.gateway_sku == "Premium"
    )
    error_message = "Use the dedicated gateway, its public frontend and immutable delegated backend, the service-selected Premium SKU, and the US foundation state."
  }

  assert {
    condition = (
      azurerm_role_assignment.foundry_user.scope == local.foundation.foundry_account_id &&
      endswith(azurerm_role_assignment.foundry_user.role_definition_id, "/53ca6127-db72-4b80-b1b0-d745d6d5456d") &&
      azurerm_role_assignment.foundry_user.principal_id == azapi_resource.gateway.identity[0].principal_id &&
      azurerm_role_assignment.foundry_user.principal_type == "ServicePrincipal" &&
      time_sleep.foundry_rbac.create_duration == "60s" &&
      azapi_resource.foundry_provider.type == "Microsoft.ApiManagement/aigateways/workspaces/modelProviders@2025-09-01-preview" &&
      azapi_resource.foundry_provider.parent_id == "${azapi_resource.gateway.id}/workspaces/default" &&
      azapi_resource.foundry_provider.body.properties.kind == "Foundry" &&
      azapi_resource.foundry_provider.body.properties.displayName == local.foundation.foundry_name &&
      azapi_resource.foundry_provider.body.properties.foundry.endpoint == "https://fdry-test01.services.ai.azure.com/" &&
      azapi_resource.foundry_provider.body.properties.foundry.resourceIds == [local.foundation.foundry_account_id] &&
      azapi_resource.foundry_provider.body.properties.foundry.authentication.kind == "ManagedIdentity" &&
      azapi_resource.foundry_provider.body.properties.foundry.authentication.managedIdentity.resource == "https://cognitiveservices.azure.com/"
    )
    error_message = "Use the account's discovered endpoint and account-scoped Foundry User for the gateway system identity, without backend keys."
  }

  assert {
    condition = (
      output.gateway_url == "https://returned-by-arm.eastus2-01.ai.gateway.azure.com" &&
      azapi_resource.runtime_key.type == "Microsoft.ApiManagement/aigateways/apiKeys@2025-09-01-preview" &&
      azapi_resource.runtime_key.name == "gateway-client" &&
      azapi_resource.runtime_key.body.properties.displayName == "All APIs subscription" &&
      length(keys(azapi_resource.runtime_key.body.properties)) == 1 &&
      length(azapi_resource.runtime_key.response_export_values) == 0
    )
    error_message = "Read the actual frontend hostname; create a runtime key without retrieving or exporting its value."
  }
}

run "registers_all_five_foundation_models" {
  command = plan

  assert {
    condition = (
      length(azapi_resource.gateway_model) == 5 &&
      length(azapi_resource.model_alias) == 5 &&
      toset([for model in values(local.models) : model.deployment_name]) == toset([
        "model-router", "gpt-6-astra", "FW-Kimi-K3", "claude-opus-5-5", "claude-opus-5-5-fast",
      ]) &&
      alltrue([
        for key, model in local.models :
        azapi_resource.gateway_model[key].type == "Microsoft.ApiManagement/aigateways/workspaces/modelProviders/models@2025-09-01-preview" &&
        azapi_resource.gateway_model[key].parent_id == azapi_resource.foundry_provider.id &&
        azapi_resource.model_alias[key].type == "Microsoft.ApiManagement/aigateways/workspaces/aliases@2025-09-01-preview" &&
        azapi_resource.model_alias[key].parent_id == "${azapi_resource.gateway.id}/workspaces/default" &&
        azapi_resource.gateway_model[key].body.properties.displayName == model.deployment_name &&
        azapi_resource.gateway_model[key].body.properties.deployment.resourceId == model.deployment_id &&
        azapi_resource.gateway_model[key].body.properties.deployment.modelName == model.deployment_name &&
        azapi_resource.gateway_model[key].body.properties.deployment.modelVersion == model.version &&
        azapi_resource.model_alias[key].body.properties.aliasName == model.deployment_name &&
        azapi_resource.model_alias[key].body.properties.backendModels[0].resourceId == azapi_resource.gateway_model[key].id
      ])
    )
    error_message = "Register each and only each foundation model and preserve its exact deployment name as the callable alias."
  }

  assert {
    condition = (
      alltrue([
        for excluded in ["claude-fable-5", "Phi", "Gpt5.4mini", "gpt-6.1-sol-mini", "FW-GLM-5.3-Flash"] :
        can(regex(local.excluded_model_pattern, excluded))
      ]) &&
      alltrue([
        for allowed in ["model-router", "gpt-6-astra", "FW-Kimi-K3", "FW-DeepSeek-V4.1-Flash", "gpt-chat-latest", "claude-opus-5-5", "claude-opus-5-5-fast"] :
        !can(regex(local.excluded_model_pattern, allowed))
      ])
    )
    error_message = "Reject every excluded model family without excluding the requested deployments."
  }

  assert {
    condition = (
      azapi_resource.gateway_model["kimi_k3"].name == "fw-kimi-k3" &&
      !can(azapi_resource.gateway_model["kimi_k3"].body.properties.apiFormat) &&
      azapi_resource.gateway_model["model_router"].body.properties.apiFormat == "OpenAIChatCompletions" &&
      azapi_resource.gateway_model["claude_opus_5_5"].body.properties.apiFormat == "AnthropicMessages" &&
      toset(azapi_resource.gateway_model["claude_opus_5_5_fast"].body.properties.supportedEndpoints) == toset(["/anthropic/v1/messages"]) &&
      toset(azapi_resource.gateway_model["gpt6_astra"].body.properties.supportedEndpoints) == toset(["/openai/v1/chat/completions"]) &&
      toset(output.model_endpoint_urls["model_router"]) == toset(["https://returned-by-arm.eastus2-01.ai.gateway.azure.com/default/models/openai/v1/chat/completions"]) &&
      toset(output.model_endpoint_urls["claude_opus_5_5"]) == toset(["https://returned-by-arm.eastus2-01.ai.gateway.azure.com/default/models/anthropic/v1/messages"])
    )
    error_message = "Honor discovered capabilities, use native Anthropic messages for Claude, and derive runtime URLs from the returned hostname."
  }
}

run "discovers_additional_endpoint_capabilities" {
  command = plan

  override_data {
    target          = data.azapi_resource.deployment["kimi_k3"]
    override_during = plan
    values = {
      output = {
        properties = {
          capabilities = { embeddings = "true", responses = "true", chatCompletion = "false" }
        }
      }
    }
  }

  assert {
    condition = tolist(azapi_resource.gateway_model["kimi_k3"].body.properties.supportedEndpoints) == tolist([
      "/openai/v1/responses",
      "/openai/v1/embeddings",
    ])
    error_message = "Use recognized capability flags in portal order rather than assuming every additional model is chat-only."
  }
}

run "uses_portal_chat_fallback_for_missing_capabilities" {
  command = plan

  override_data {
    target          = data.azapi_resource.deployment["kimi_k3"]
    override_during = plan
    values          = { output = { properties = {} } }
  }

  assert {
    condition     = toset(azapi_resource.gateway_model["kimi_k3"].body.properties.supportedEndpoints) == toset(["/openai/v1/chat/completions"])
    error_message = "Match the official portal's chat fallback when no capabilities are present."
  }
}

run "rejects_unrecognized_advertised_capabilities" {
  command = plan

  override_data {
    target          = data.azapi_resource.deployment["kimi_k3"]
    override_during = plan
    values          = { output = { properties = { capabilities = { unrecognized = "true" } } } }
  }

  expect_failures = [azapi_resource.gateway_model["kimi_k3"]]
}

run "accepts_reviewed_endpoint_override" {
  command = plan

  variables {
    model_endpoint_overrides = {
      kimi_k3 = ["/openai/v1/embeddings"]
    }
  }

  override_data {
    target          = data.azapi_resource.deployment["kimi_k3"]
    override_during = plan
    values          = { output = { properties = { capabilities = { unrecognized = "true" } } } }
  }

  assert {
    condition     = toset(azapi_resource.gateway_model["kimi_k3"].body.properties.supportedEndpoints) == toset(["/openai/v1/embeddings"])
    error_message = "A reviewed endpoint override must allow an otherwise unrecognized model capability."
  }
}

run "rejects_unknown_override_key" {
  command = plan

  variables {
    model_endpoint_overrides = {
      nonexistent = ["/openai/v1/chat/completions"]
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_unsupported_override_path" {
  command = plan

  variables {
    model_endpoint_overrides = {
      kimi_k3 = ["/invented/endpoint"]
    }
  }

  expect_failures = [var.model_endpoint_overrides]
}

run "rejects_old_subnet_delegation" {
  command = plan

  override_data {
    target          = data.azapi_resource.gateway_subnet
    override_during = plan
    values = {
      output = {
        properties = {
          delegations = [{ properties = { serviceName = "Microsoft.Web/serverFarms" } }]
        }
      }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_backend_vnet_in_wrong_region" {
  command = plan

  override_data {
    target          = data.azapi_resource.gateway_vnet
    override_during = plan
    values          = { output = { location = "swedencentral" } }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_public_or_key_enabled_foundry" {
  command = plan

  override_data {
    target          = data.azapi_resource.foundry_account
    override_during = plan
    values = {
      output = {
        location = "eastus2"
        properties = {
          endpoint            = "https://fdry-test01.services.ai.azure.com/"
          disableLocalAuth    = false
          publicNetworkAccess = "Enabled"
        }
      }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_invalid_names" {
  command = plan

  variables {
    gateway_name     = "UPPERCASE"
    runtime_key_name = "bad_key"
  }

  expect_failures = [var.gateway_name, var.runtime_key_name]
}

run "registers_future_foundation_deployments" {
  command = plan

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        gateway_foundation = {
          subscription_id     = "00000000-0000-0000-0000-000000000000"
          tenant_id           = "11111111-1111-4111-8111-111111111111"
          resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
          resource_group_name = "rg-test"
          location            = "eastus2"
          tags                = {}
          name_suffix         = "test01"
          foundry_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
          foundry_name        = "fdry-test01"
          outbound_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/gateway-outbound"
          models = {
            deepseek = {
              deployment_name = "FW-DeepSeek-V4.1-Flash"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/FW-DeepSeek-V4.1-Flash"
              format          = "DeepSeek"
              catalog_name    = "DeepSeek-V4-Flash"
              version         = "2026-04-23"
            }
            gpt_chat_latest = {
              deployment_name = "gpt-chat-latest"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/gpt-chat-latest"
              format          = "OpenAI"
              catalog_name    = "gpt-chat-latest"
              version         = "2026-10-07"
            }
            future_model = {
              deployment_name = "future-embedding-model"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/future-embedding-model"
              format          = "OpenAI"
              catalog_name    = "future-embedding-model"
              version         = "1"
            }
          }
        }
      }
    }
  }

  override_data {
    target          = data.azapi_resource.deployment["gpt_chat_latest"]
    override_during = plan
    values = {
      output = { properties = { capabilities = { chatCompletion = "true", responses = "true" } } }
    }
  }

  override_data {
    target          = data.azapi_resource.deployment["future_model"]
    override_during = plan
    values          = { output = { properties = { capabilities = { embeddings = "true" } } } }
  }

  assert {
    condition = (
      toset(keys(azapi_resource.gateway_model)) == toset(["deepseek", "gpt_chat_latest", "future_model"]) &&
      azapi_resource.model_alias["deepseek"].body.properties.aliasName == "FW-DeepSeek-V4.1-Flash" &&
      azapi_resource.model_alias["gpt_chat_latest"].body.properties.aliasName == "gpt-chat-latest" &&
      azapi_resource.gateway_model["gpt_chat_latest"].body.properties.deployment.modelVersion == "2026-10-07" &&
      azapi_resource.gateway_model["gpt_chat_latest"].body.properties.apiFormat == "OpenAIChatCompletions" &&
      toset(azapi_resource.gateway_model["gpt_chat_latest"].body.properties.supportedEndpoints) == toset(["/openai/v1/chat/completions", "/openai/v1/responses"]) &&
      toset(azapi_resource.gateway_model["future_model"].body.properties.supportedEndpoints) == toset(["/openai/v1/embeddings"])
    )
    error_message = "Newly deployed foundation models must be registered automatically, including the latest chat model and its advertised endpoints."
  }
}

run "rejects_colliding_model_resource_names" {
  command = plan

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        gateway_foundation = {
          subscription_id     = "00000000-0000-0000-0000-000000000000"
          tenant_id           = "11111111-1111-4111-8111-111111111111"
          resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
          resource_group_name = "rg-test"
          location            = "eastus2"
          tags                = {}
          name_suffix         = "test01"
          foundry_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
          foundry_name        = "fdry-test01"
          outbound_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/gateway-outbound"
          models = {
            first = {
              deployment_name = "chat.model"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/chat.model"
              format          = "OpenAI"
              catalog_name    = "chat.model"
              version         = "1"
            }
            second = {
              deployment_name = "chat-model"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/chat-model"
              format          = "OpenAI"
              catalog_name    = "chat-model"
              version         = "1"
            }
          }
        }
      }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_models_from_a_different_account" {
  command = plan

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        gateway_foundation = {
          subscription_id     = "00000000-0000-0000-0000-000000000000"
          tenant_id           = "11111111-1111-4111-8111-111111111111"
          resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
          resource_group_name = "rg-test"
          location            = "eastus2"
          tags                = {}
          name_suffix         = "test01"
          foundry_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
          foundry_name        = "fdry-test01"
          outbound_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/gateway-outbound"
          models = {
            misplaced = {
              deployment_name = "another-model"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/other-account/deployments/another-model"
              format          = "OpenAI"
              catalog_name    = "another-model"
              version         = "1"
            }
          }
        }
      }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_foundation_in_wrong_region" {
  command = plan

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        gateway_foundation = {
          subscription_id     = "00000000-0000-0000-0000-000000000000"
          tenant_id           = "11111111-1111-4111-8111-111111111111"
          resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
          resource_group_name = "rg-test"
          location            = "swedencentral"
          tags                = {}
          name_suffix         = "test01"
          foundry_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
          foundry_name        = "fdry-test01"
          outbound_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/gateway-outbound"
          models              = {}
        }
      }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_excluded_legacy_models" {
  command = plan

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        gateway_foundation = {
          subscription_id     = "00000000-0000-0000-0000-000000000000"
          tenant_id           = "11111111-1111-4111-8111-111111111111"
          resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
          resource_group_name = "rg-test"
          location            = "eastus2"
          tags                = {}
          name_suffix         = "test01"
          foundry_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01"
          foundry_name        = "fdry-test01"
          outbound_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/gateway-outbound"
          models = {
            legacy = {
              deployment_name = "FW-GLM-5.3-Flash"
              deployment_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/fdry-test01/deployments/FW-GLM-5.3-Flash"
              format          = "Fireworks"
              catalog_name    = "FW-GLM-5.3-Flash"
              version         = "1"
            }
          }
        }
      }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "rejects_nonpremium_service_sku" {
  command = plan

  override_resource {
    target          = azapi_resource.gateway
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/aigateways/aigw-us-test01"
      identity = {
        principal_id = "22222222-2222-4222-8222-222222222222"
        tenant_id    = "11111111-1111-4111-8111-111111111111"
      }
      output = { sku = { name = "Basic" } }
    }
  }

  expect_failures = [azapi_resource.gateway]
}

run "does_not_invent_missing_hostname" {
  command = plan

  override_resource {
    target          = azapi_resource.gateway
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ApiManagement/aigateways/aigw-us-test01"
      identity = {
        principal_id = "22222222-2222-4222-8222-222222222222"
        tenant_id    = "11111111-1111-4111-8111-111111111111"
      }
      output = {
        sku        = { name = "Premium" }
        properties = { frontend = {} }
      }
    }
  }

  assert {
    condition     = output.gateway_url == null && output.model_endpoint_urls == null
    error_message = "Do not fabricate runtime URLs when the service has not returned a hostname."
  }
}
