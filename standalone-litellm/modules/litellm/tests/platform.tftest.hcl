mock_provider "azurerm" {}
mock_provider "random" {
  mock_resource "random_string" {
    defaults = { result = "abc123" }
  }
  mock_resource "random_password" {
    defaults = { result = "OnlyMockPasswordNeverARealCredential123456" }
  }
}

variables {
  settings = {
    name                  = "unit-test"
    location              = "northcentralus"
    image                 = "ghcr.io/berriai/litellm@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    allowed_ingress_cidrs = ["203.0.113.10/32"]
  }
}

run "private_data_and_revision_safety" {
  command = plan
  assert {
    condition     = azurerm_postgresql_flexible_server.this.public_network_access_enabled == false && azurerm_managed_redis.this.public_network_access == "Disabled"
    error_message = "Databases must not expose public network access."
  }
  assert {
    condition     = azurerm_postgresql_flexible_server.this.backup_retention_days == 7
    error_message = "Native PaaS backup retention must default to seven days."
  }
  assert {
    condition     = azurerm_managed_redis.this.default_database[0].client_protocol == "Encrypted" && azurerm_managed_redis.this.default_database[0].clustering_policy == "NoCluster"
    error_message = "Redis must require TLS and noncluster client semantics."
  }
  assert {
    condition     = azurerm_container_app.this.revision_mode == "Multiple" && azurerm_container_app.this.template[0].min_replicas >= 1
    error_message = "Rollouts need multiple revisions and a warm replica."
  }
  assert {
    condition     = one(azurerm_container_app.this.template[0].container[0].readiness_probe).path == "/health/readiness"
    error_message = "Application readiness must gate serving traffic."
  }
  assert {
    condition     = local.config.litellm_settings.cache_params.ssl && length(local.config.litellm_settings.cache_params.supported_call_types) == 0
    error_message = "Redis TLS required; response caching disabled by default."
  }
}

run "provider_agnostic_models_and_secret_refs" {
  command = plan
  variables {
    settings = {
      name                  = "unit-test"
      location              = "northcentralus"
      image                 = "ghcr.io/berriai/litellm:v1.100.0"
      allowed_ingress_cidrs = ["203.0.113.10/32"]
      provider_environment  = { OPENAI_API_BASE = "https://api.example.invalid/v1" }
      model_list = [{
        model_name = "generic"
        litellm_params = {
          model   = "openai/test-model"
          api_key = "os.environ/OPENAI_API_KEY"
        }
      }]
    }
    provider_secrets = { OPENAI_API_KEY = "mock$key$$literal" }
  }
  assert {
    condition     = local.config.model_list[0].litellm_params.model == "openai/test-model"
    error_message = "Models must not be hardcoded to Foundry."
  }
  assert {
    condition     = one([for env in azurerm_container_app.this.template[0].container[0].env : env if env.name == "OPENAI_API_KEY"]).secret_name == "provider-${substr(sha256("OPENAI_API_KEY"), 0, 16)}"
    error_message = "Provider credentials must use secretrefs."
  }
  assert {
    condition     = one([for s in azurerm_container_app.this.secret : s if startswith(s.name, "provider-")]).value == "mock$$key$$$$literal"
    error_message = "Literal dollars must survive ACA environment expansion."
  }
}

run "internal_dns_and_explicit_traffic" {
  command = plan
  variables {
    settings = {
      name                  = "unit-test"
      location              = "northcentralus"
      image                 = "ghcr.io/berriai/litellm:v1.100.0"
      allowed_ingress_cidrs = ["10.80.0.0/16"]
      private_ingress       = true
      traffic_weights       = { "old" = 95, "new" = 5 }
    }
  }
  assert {
    condition     = length(azurerm_private_dns_zone.aca) == 1 && azurerm_private_dns_a_record.aca[0].name == "*"
    error_message = "Internal ingress requires wildcard private DNS."
  }
  assert {
    condition     = azurerm_container_app_environment.this.internal_load_balancer_enabled && azurerm_container_app_environment.this.public_network_access == "Disabled"
    error_message = "Private ingress must stay private."
  }
  assert {
    condition     = alltrue([for weight in azurerm_container_app.this.ingress[0].traffic_weight : !weight.latest_revision])
    error_message = "Explicit rollout weights must never route to latest."
  }
}

run "reject_world_ingress" {
  command = plan
  variables {
    settings = {
      name = "unit-test", location = "northcentralus", image = "image:v1.100.0", allowed_ingress_cidrs = ["0.0.0.0/0"]
    }
  }
  expect_failures = [var.settings]
}

run "reject_mutable_image" {
  command = plan
  variables {
    settings = {
      name = "unit-test", location = "northcentralus", image = "image:latest", allowed_ingress_cidrs = ["203.0.113.10/32"]
    }
  }
  expect_failures = [var.settings]
}

run "reject_invalid_traffic" {
  command = plan
  variables {
    settings = {
      name = "unit-test", location = "northcentralus", image = "image:v1.100.0", allowed_ingress_cidrs = ["203.0.113.10/32"], traffic_weights = { old = 95, new = 10 }
    }
  }
  expect_failures = [var.settings]
}

run "reject_reserved_variables" {
  command = plan
  variables {
    provider_secrets = { DATABASE_URL = "not-allowed" }
  }
  expect_failures = [azurerm_container_app.this]
}

run "reject_invalid_backup_retention" {
  command = plan
  variables {
    settings = {
      name = "unit-test", location = "northcentralus", image = "image:v1.100.0", allowed_ingress_cidrs = ["203.0.113.10/32"], postgres_backup_days = 36
    }
  }
  expect_failures = [var.settings]
}