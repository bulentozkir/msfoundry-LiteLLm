terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  features {}
}

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

data "azurerm_cognitive_account" "foundry" {
  name                = var.foundry_account_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

data "azurerm_service_plan" "existing" {
  name                = var.app_service_plan_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

locals {
  litellm_name = "ca-litellm-${var.name_suffix}"
  litellm_config = {
    model_list = [
      {
        model_name = "gpt-5.4-mini"
        litellm_params = {
          model       = "azure/Gpt5.4mini"
          api_base    = "https://${var.foundry_account_name}.openai.azure.com"
          api_version = "2025-04-01-preview"
        }
      },
      {
        model_name = "phi-4"
        litellm_params = {
          model       = "azure_ai/Phi"
          api_base    = "https://${var.foundry_account_name}.services.ai.azure.com/models"
          api_version = "2024-05-01-preview"
        }
      },
      {
        model_name = "FW-DeepSeek-V4.1-Flash"
        litellm_params = {
          model       = "azure_ai/FW-DeepSeek-V4.1-Flash"
          api_base    = "https://${var.foundry_account_name}.services.ai.azure.com/models"
          api_version = "2024-05-01-preview"
        }
      },
    ]
    litellm_settings = {
      enable_azure_ad_token_refresh = true
      drop_params                   = true
      set_verbose                   = false
      json_logs                     = true
      request_timeout               = 90
      cache                         = true
      enable_redis_auth_cache       = true
      cache_params = {
        type               = "redis"
        host               = "os.environ/REDIS_HOST"
        port               = "os.environ/REDIS_PORT"
        ssl                = true
        ssl_cert_reqs      = "required"
        ssl_check_hostname = true
        mode               = "default_off"
        ttl                = 600
      }
    }
    router_settings = {
      redis_host = "os.environ/REDIS_HOST"
      redis_port = "os.environ/REDIS_PORT"
      cache_kwargs = {
        ssl                = true
        ssl_cert_reqs      = "required"
        ssl_check_hostname = true
      }
    }
    general_settings = {
      master_key                     = "os.environ/LITELLM_MASTER_KEY"
      database_url                   = "os.environ/DATABASE_URL"
      database_connection_pool_limit = 5
      store_model_in_db              = true
      store_prompts_in_spend_logs    = false
      database_extra_connection_params = {
        sslmode   = "require"
        sslaccept = "strict"
      }
    }
  }
}

resource "random_password" "proxy_key" {
  length  = 48
  special = false
}

resource "azurerm_user_assigned_identity" "litellm" {
  name                = "id-litellm-${var.name_suffix}"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "litellm_foundry_user" {
  scope                            = data.azurerm_cognitive_account.foundry.id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id                     = azurerm_user_assigned_identity.litellm.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_log_analytics_workspace" "litellm" {
  name                = "log-litellm-${var.name_suffix}"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.1
  tags                = var.tags
}

resource "azurerm_container_app_environment" "litellm" {
  name                       = "cae-litellm-${var.name_suffix}"
  resource_group_name        = data.azurerm_resource_group.existing.name
  location                   = data.azurerm_resource_group.existing.location
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.litellm.id
  tags                       = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }
}

resource "azurerm_container_app" "litellm" {
  name                         = local.litellm_name
  resource_group_name          = data.azurerm_resource_group.existing.name
  container_app_environment_id = azurerm_container_app_environment.litellm.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.litellm.id]
  }

  secret {
    name  = "proxy-key"
    value = "sk-${random_password.proxy_key.result}"
  }

  secret {
    name  = "salt-key"
    value = random_password.salt_key.result
  }

  template {
    min_replicas = 0
    max_replicas = 1

    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }

    container {
      name    = "litellm"
      image   = var.litellm_image
      cpu     = 1.0
      memory  = "2Gi"
      command = ["/bin/sh", "-c"]
      args    = ["printf '%s' \"$LITELLM_CONFIG_BASE64\" | base64 -d > /tmp/litellm.yaml && exec litellm --config /tmp/litellm.yaml --port 4000 --num_workers 1"]

      env {
        name  = "LITELLM_CONFIG_BASE64"
        value = base64encode(yamlencode(local.litellm_config))
      }
      env {
        name        = "LITELLM_MASTER_KEY"
        secret_name = "proxy-key"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.litellm.client_id
      }
      env {
        name  = "DISABLE_SCHEMA_UPDATE"
        value = "false"
      }
      env {
        name  = "ENFORCE_PRISMA_MIGRATION_CHECK"
        value = "true"
      }
      env {
        name  = "AZURE_POSTGRESQL_AUTH"
        value = "true"
      }
      env {
        name  = "DATABASE_HOST"
        value = azurerm_postgresql_flexible_server.litellm.fqdn
      }
      env {
        name  = "DATABASE_PORT"
        value = "5432"
      }
      env {
        name  = "DATABASE_NAME"
        value = azurerm_postgresql_flexible_server_database.litellm.name
      }
      env {
        name  = "DATABASE_USER"
        value = azurerm_user_assigned_identity.litellm.name
      }
      env {
        name        = "LITELLM_SALT_KEY"
        secret_name = "salt-key"
      }
      env {
        name  = "REDIS_HOST"
        value = azurerm_managed_redis.litellm.hostname
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(azurerm_managed_redis.litellm.default_database[0].port)
      }
      env {
        name  = "REDIS_AZURE_AD_TOKEN"
        value = "true"
      }
      env {
        name  = "REDIS_USERNAME"
        value = azurerm_user_assigned_identity.litellm.principal_id
      }
      env {
        name  = "REDIS_SSL"
        value = "True"
      }
      env {
        name  = "PROXY_BASE_URL"
        value = "https://${local.litellm_name}.${azurerm_container_app_environment.litellm.default_domain}"
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 4000
        path                    = "/health/liveliness"
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 60
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = 4000
        path                    = "/health/readiness"
        interval_seconds        = 10
        timeout                 = 5
        success_count_threshold = 1
        failure_count_threshold = 3
      }
      liveness_probe {
        transport               = "HTTP"
        port                    = 4000
        path                    = "/health/liveliness"
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 5
      }
    }
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = 4000
    transport                  = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_role_assignment.litellm_foundry_user,
    azurerm_postgresql_flexible_server_active_directory_administrator.litellm,
    azurerm_postgresql_flexible_server_firewall_rule.litellm,
    azurerm_managed_redis_access_policy_assignment.litellm,
  ]
}

resource "azurerm_linux_web_app" "app2" {
  name                = "foundry-chat2-${var.name_suffix}"
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_service_plan.existing.location
  service_plan_id     = data.azurerm_service_plan.existing.id
  https_only          = true

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = true
  tags                                           = var.tags

  site_config {
    always_on           = false
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"

    application_stack {
      dotnet_version = "10.0"
    }
  }

  app_settings = {
    "Mlflow__BaseUrl"                = "https://${azurerm_container_app.litellm.ingress[0].fqdn}"
    "Mlflow__ApiKey"                 = "sk-${random_password.proxy_key.result}"
    "Mlflow__Model"                  = "gpt-5.4-mini"
    "Mlflow__PhiModel"               = "phi-4"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
  }
}