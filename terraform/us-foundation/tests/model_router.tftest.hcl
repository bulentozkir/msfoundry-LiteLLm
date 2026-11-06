variables {
  claude_provider_data = {
    organizationName = "Contoso"
    countryCode      = "US"
    industry         = "technology"
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway"
      name     = "rg-foundry-aigateway"
      location = "eastus2"
      tags     = {}
    }
  }

  mock_resource "azurerm_cognitive_deployment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01/deployments/model-router"
    }
  }
}

mock_provider "azapi" {
  mock_data "azapi_resource" {
    override_during = plan
    defaults = {
      output = { properties = { state = "Registered" } }
    }
  }

  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01/deployments/model-router"
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

override_resource {
  target          = azapi_resource.foundry
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01"
  }
}

override_data {
  target          = data.azapi_resource.model_router_current
  override_during = plan
  values = {
    exists = false
    output = null
    tags   = null
  }
}

run "preserves_live_subset_and_targets_one_million_tpm" {
  command = plan

  assert {
    condition = (
      azapi_resource.model_router.type == "Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview" &&
      azapi_resource.model_router.name == "model-router" &&
      azapi_resource.model_router.body.sku.name == "GlobalStandard" &&
      azapi_resource.model_router.body.sku.capacity == 1000 &&
      azapi_resource.model_router.body.properties.model.format == "OpenAI" &&
      azapi_resource.model_router.body.properties.model.name == "model-router" &&
      azapi_resource.model_router.body.properties.model.version == "2025-11-18" &&
      azapi_resource.model_router.body.properties.versionUpgradeOption == "NoAutoUpgrade" &&
      azapi_resource.model_router.body.properties.routing.mode == "balanced" &&
      output.gateway_foundation.models.model_router.capacity == 1000 &&
      !contains(keys(azurerm_cognitive_deployment.model), "model_router")
    )
    error_message = "The router must have one AzAPI owner, its existing identity and version, balanced routing, and 1,000 capacity units."
  }

  assert {
    condition = (
      length(azapi_resource.model_router.body.properties.routing.models) == 4 &&
      toset([
        for model in azapi_resource.model_router.body.properties.routing.models :
        "${model.format}|${model.name}|${model.version}"
        ]) == toset([
        "OpenAI|gpt-6-astra|2026-09-03",
        "OpenAI|gpt-5.6-sol|2026-07-09",
        "OpenAI|gpt-5.6-terra|2026-07-09",
        "Fireworks|FW-Kimi-K3|1",
      ]) &&
      alltrue([
        for model in azapi_resource.model_router.body.properties.routing.models :
        !strcontains(lower(model.name), "glm")
      ]) &&
      !azapi_resource.model_router.ignore_missing_property &&
      azapi_resource.model_router.list_unique_id_property["properties.routing.models"] == "name,version"
    )
    error_message = "Preserve the exact four-model subset, exclude GLM, and detect missing, extra, or reordered model entries correctly."
  }
}

run "supports_a_smaller_explicit_subset" {
  command = plan

  variables {
    model_router_routing_models = [
      { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
      { format = "Fireworks", name = "FW-Kimi-K3", version = "1" },
    ]
  }

  assert {
    condition = (
      length(azapi_resource.model_router.body.properties.routing.models) == 2 &&
      toset([for model in azapi_resource.model_router.body.properties.routing.models : model.name]) ==
      toset(["gpt-6-astra", "FW-Kimi-K3"]) &&
      azapi_resource.model_router.body.sku.capacity == 1000
    )
    error_message = "A subset change must replace the entire list without changing router capacity."
  }
}

run "preserves_other_writable_deployment_settings" {
  command = plan

  override_data {
    target          = data.azapi_resource.model_router_current
    override_during = plan
    values = {
      exists = true
      tags   = { owner = "example" }
      output = {
        sku = {
          name     = "GlobalStandard"
          capacity = 100
          family   = "example-family"
          size     = "example-size"
          tier     = "Standard"
        }
        properties = {
          provisioningState        = "Succeeded"
          dynamicThrottlingEnabled = false
          currentCapacity          = 100
          deploymentState          = "Running"
          parentDeploymentName     = "existing-parent"
          raiPolicyName            = "existing-policy"
          serviceTier              = "Default"
          spilloverDeploymentName  = "existing-spillover"
          capacitySettings         = { designatedCapacity = 100, priority = 1 }
          scaleSettings            = { scaleType = "Standard", capacity = 100, activeCapacity = 90 }
          routing = {
            mode = "cost"
            models = [
              { format = "Fireworks", name = "FW-GLM-5.3-Flash", version = "1" },
              { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
            ]
          }
          model = {
            publisher     = "existing-publisher"
            source        = "existing-source"
            sourceAccount = "existing-account"
            callRateLimit = { count = 1 }
          }
        }
      }
    }
  }

  assert {
    condition = (
      azapi_resource.model_router.tags.owner == "example" &&
      azapi_resource.model_router.body.sku.capacity == 1000 &&
      azapi_resource.model_router.body.sku.family == "example-family" &&
      azapi_resource.model_router.body.sku.size == "example-size" &&
      azapi_resource.model_router.body.sku.tier == "Standard" &&
      azapi_resource.model_router.body.properties.raiPolicyName == "existing-policy" &&
      azapi_resource.model_router.body.properties.currentCapacity == 100 &&
      azapi_resource.model_router.body.properties.deploymentState == "Running" &&
      azapi_resource.model_router.body.properties.parentDeploymentName == "existing-parent" &&
      azapi_resource.model_router.body.properties.serviceTier == "Default" &&
      azapi_resource.model_router.body.properties.spilloverDeploymentName == "existing-spillover" &&
      azapi_resource.model_router.body.properties.capacitySettings.designatedCapacity == 100 &&
      azapi_resource.model_router.body.properties.scaleSettings.capacity == 100 &&
      azapi_resource.model_router.body.properties.model.publisher == "existing-publisher" &&
      azapi_resource.model_router.body.properties.model.source == "existing-source" &&
      azapi_resource.model_router.body.properties.model.sourceAccount == "existing-account" &&
      azapi_resource.model_router.body.properties.routing.mode == "balanced" &&
      length(azapi_resource.model_router.body.properties.routing.models) == 4 &&
      alltrue([
        for model in azapi_resource.model_router.body.properties.routing.models :
        !strcontains(lower(model.name), "glm")
      ]) &&
      !contains(keys(azapi_resource.model_router.body.properties), "provisioningState") &&
      !contains(keys(azapi_resource.model_router.body.properties), "dynamicThrottlingEnabled") &&
      !contains(keys(azapi_resource.model_router.body.properties.scaleSettings), "activeCapacity") &&
      !contains(keys(azapi_resource.model_router.body.properties.model), "callRateLimit")
    )
    error_message = "The full PUT must retain unrelated writable settings while excluding read-only API fields."
  }
}

run "rejects_an_empty_subset" {
  command = plan

  variables {
    model_router_routing_models = []
  }

  expect_failures = [var.model_router_routing_models]
}

run "rejects_a_single_model_subset" {
  command = plan

  variables {
    model_router_routing_models = [
      { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
    ]
  }

  expect_failures = [var.model_router_routing_models]
}

run "rejects_duplicate_model_identities" {
  command = plan

  variables {
    model_router_routing_models = [
      { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
      { format = "OpenAI", name = "GPT-6-ASTRA", version = "2026-09-03" },
    ]
  }

  expect_failures = [var.model_router_routing_models]
}

run "rejects_blank_model_fields" {
  command = plan

  variables {
    model_router_routing_models = [
      { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
      { format = "Fireworks", name = " ", version = "1" },
    ]
  }

  expect_failures = [var.model_router_routing_models]
}

run "rejects_null_model_fields" {
  command = plan

  variables {
    model_router_routing_models = [
      { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
      { format = "Fireworks", name = "FW-Kimi-K3", version = null },
    ]
  }

  expect_failures = [var.model_router_routing_models]
}

run "seed_legacy_router" {
  command   = apply
  state_key = "router_migration"

  module {
    source = ".\\tests\\fixtures\\legacy_router"
  }
}

run "plans_router_ownership_migration" {
  command   = plan
  state_key = "router_migration"

  override_resource {
    target          = azapi_resource.foundry
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01"
    }
  }

  assert {
    condition = (
      azapi_resource.model_router.id == run.seed_legacy_router.router_id &&
      azapi_resource.model_router.name == "model-router" &&
      azapi_resource.model_router.body.sku.capacity == 1000 &&
      !contains(keys(azurerm_cognitive_deployment.model), "model_router")
    )
    error_message = "The legacy router must move to the sole AzAPI owner with the requested capacity."
  }
}

run "seed_router_policy" {
  command   = apply
  state_key = "router_policy"

  module {
    source = ".\\tests\\fixtures\\current_router"
  }
}

run "keeps_an_unchanged_router" {
  command   = plan
  state_key = "router_policy"

  override_resource {
    target          = azapi_resource.foundry
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01"
    }
  }

  assert {
    condition = (
      azapi_resource.model_router.id == run.seed_router_policy.router_id &&
      output.gateway_foundation.models.model_router.deployment_id == azapi_resource.model_router.id &&
      azapi_resource.model_router.body.sku.capacity == 1000 &&
      length(azapi_resource.model_router.body.properties.routing.models) == 4
    )
    error_message = "An unchanged policy must keep the existing router and gateway output identity."
  }
}

run "updates_the_subset_in_place" {
  command   = plan
  state_key = "router_policy"

  override_resource {
    target          = azapi_resource.foundry
    override_during = plan
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-aigateway/providers/Microsoft.CognitiveServices/accounts/fdry-aigw-us-test01"
    }
  }

  variables {
    model_router_routing_models = [
      { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
      { format = "Fireworks", name = "FW-Kimi-K3", version = "1" },
    ]
  }

  assert {
    condition = (
      azapi_resource.model_router.id == run.seed_router_policy.router_id &&
      length(azapi_resource.model_router.body.properties.routing.models) == 2 &&
      azapi_resource.model_router.body.sku.capacity == 1000
    )
    error_message = "Removing models from the subset must retain the router identity and capacity."
  }
}
