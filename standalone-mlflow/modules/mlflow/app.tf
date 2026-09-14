resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = local.cfg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${local.name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = local.cfg.location
  infrastructure_subnet_id       = azurerm_subnet.aca.id
  internal_load_balancer_enabled = local.cfg.private_ingress
  public_network_access          = local.cfg.private_ingress ? "Disabled" : "Enabled"
  logs_destination               = "log-analytics"
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  tags                           = local.tags
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = local.cfg.location
  tags                = local.tags
}

resource "random_password" "master" {
  length  = 48
  special = false
}
resource "random_password" "ui" {
  length  = 32
  special = false
}
resource "random_password" "salt" {
  length  = 48
  special = false
}

locals {
  proxy_url = coalesce(local.cfg.public_base_url, "https://${local.app_name}.${azurerm_container_app_environment.this.default_domain}")
  reserved_environment = [
    "LITELLM_MASTER_KEY", "LITELLM_SALT_KEY", "DATABASE_URL", "REDIS_HOST", "REDIS_PORT",
    "REDIS_PASSWORD", "REDIS_SSL", "UI_USERNAME", "UI_PASSWORD", "PROXY_BASE_URL",
    "AZURE_CLIENT_ID", "LITELLM_CONFIG_BASE64", "DISABLE_SCHEMA_UPDATE", "LITELLM_MODE",
  ]
  config = {
    model_list = local.cfg.model_list
    litellm_settings = {
      enable_azure_ad_token_refresh = true
      set_verbose                   = false
      json_logs                     = true
      request_timeout               = 120
      cache                         = true
      cache_params = {
        type                 = "redis"
        host                 = "os.environ/REDIS_HOST"
        port                 = "os.environ/REDIS_PORT"
        password             = "os.environ/REDIS_PASSWORD"
        ssl                  = true
        supported_call_types = []
      }
    }
    router_settings = {
      redis_host     = "os.environ/REDIS_HOST"
      redis_port     = "os.environ/REDIS_PORT"
      redis_password = "os.environ/REDIS_PASSWORD"
      cache_kwargs   = { ssl = true }
    }
    general_settings = {
      master_key                     = "os.environ/LITELLM_MASTER_KEY"
      database_url                   = "os.environ/DATABASE_URL"
      store_model_in_db              = true
      database_connection_pool_limit = local.cfg.database_pool_limit
    }
  }
  secret_values = merge({
    "master-key"   = "sk-${random_password.master.result}"
    "salt-key"     = "sk-${random_password.salt.result}"
    "ui-password"  = random_password.ui.result
    "database-url" = "postgresql://litellmadmin:${random_password.postgres.result}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/litellm?sslmode=require"
    "redis-key"    = azurerm_managed_redis.this.default_database[0].primary_access_key
  }, { for name, value in var.provider_secrets : "provider-${substr(sha256(name), 0, 16)}" => value })
  secret_environment = merge({
    LITELLM_MASTER_KEY = "master-key"
    LITELLM_SALT_KEY   = "salt-key"
    UI_PASSWORD        = "ui-password"
    DATABASE_URL       = "database-url"
    REDIS_PASSWORD     = "redis-key"
  }, { for name in nonsensitive(keys(var.provider_secrets)) : name => "provider-${substr(sha256(name), 0, 16)}" })
  environment = merge(local.cfg.provider_environment, {
    LITELLM_CONFIG_BASE64 = base64encode(yamlencode(local.config))
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.this.client_id
    REDIS_HOST            = azurerm_managed_redis.this.hostname
    REDIS_PORT            = tostring(azurerm_managed_redis.this.default_database[0].port)
    REDIS_SSL             = "True"
    UI_USERNAME           = local.cfg.ui_username
    PROXY_BASE_URL        = local.proxy_url
    DISABLE_SCHEMA_UPDATE = tostring(local.cfg.disable_schema_update)
    LITELLM_MODE          = "PRODUCTION"
  })
}

resource "azurerm_container_app" "this" {
  name                         = local.app_name
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Multiple"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }
  dynamic "secret" {
    for_each = nonsensitive(toset(keys(local.secret_values)))
    content {
      name = secret.value
      # ACA expands $$ to $ in environment values; preserve literal dollars.
      value = replace(local.secret_values[secret.value], "$", "$$")
    }
  }

  template {
    revision_suffix                  = local.cfg.revision_suffix
    min_replicas                     = local.cfg.min_replicas
    max_replicas                     = local.cfg.max_replicas
    termination_grace_period_seconds = 300
    http_scale_rule {
      name                = "http"
      concurrent_requests = tostring(local.cfg.http_concurrency)
    }
    container {
      name   = "litellm"
      image  = local.cfg.image
      cpu    = local.cfg.cpu
      memory = local.cfg.memory
      # Base64 avoids shell interpolation of model config; exec preserves SIGTERM.
      command = ["/bin/sh", "-c"]
      args    = ["printf '%s' \"$LITELLM_CONFIG_BASE64\" | base64 -d > /tmp/litellm.yaml && exec litellm --config /tmp/litellm.yaml --port 4000 --num_workers 1"]

      dynamic "env" {
        for_each = local.environment
        content {
          name  = env.key
          value = replace(env.value, "$", "$$")
        }
      }
      dynamic "env" {
        for_each = local.secret_environment
        content {
          name        = env.key
          secret_name = env.value
        }
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
    dynamic "ip_security_restriction" {
      for_each = toset(local.cfg.allowed_ingress_cidrs)
      content {
        name             = "allow-${replace(ip_security_restriction.value, "/", "-")}"
        action           = "Allow"
        ip_address_range = ip_security_restriction.value
      }
    }
    # latest=100 is bootstrap only. Freeze to an explicit revision before upgrading.
    dynamic "traffic_weight" {
      for_each = length(local.cfg.traffic_weights) == 0 ? { latest = 100 } : local.cfg.traffic_weights
      content {
        latest_revision = traffic_weight.key == "latest"
        revision_suffix = traffic_weight.key == "latest" ? null : trimprefix(traffic_weight.key, "${local.app_name}--")
        percentage      = traffic_weight.value
      }
    }
  }

  lifecycle {
    precondition {
      condition = length(setintersection(toset(local.reserved_environment), toset(concat(
        keys(local.cfg.provider_environment), nonsensitive(keys(var.provider_secrets))
      )))) == 0 && length(setintersection(toset(keys(local.cfg.provider_environment)), toset(nonsensitive(keys(var.provider_secrets))))) == 0
      error_message = "Provider environment/secrets cannot override reserved LiteLLM variables or use duplicate names."
    }
    precondition {
      condition     = alltrue([for name in concat(keys(local.cfg.provider_environment), nonsensitive(keys(var.provider_secrets))) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name))])
      error_message = "Provider environment names must be valid shell-style environment variable names."
    }
  }
  depends_on = [
    azurerm_postgresql_flexible_server_database.this,
    azurerm_private_endpoint.redis,
    azurerm_private_dns_zone_virtual_network_link.redis,
  ]
}