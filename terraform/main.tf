resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Container Apps environment
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id   = azurerm_subnet.aca.id
  # Public again at the user's explicit request (Front Door Standard can't
  # reach a private-only environment - Private Link to origin needs Premium,
  # already declined for cost). Both container apps' ingress is locked down
  # to Front Door's published IP ranges via ip_security_restriction below -
  # weaker than the FDID-header check used for chat-client2 (Container Apps
  # only supports CIDR ranges, not service tags or header matching).
  tags = var.tags

  # Keep the existing Consumption workload profile explicit so Terraform does
  # not repeatedly plan to remove Azure's persisted default profile metadata.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }
}

# ---------------------------------------------------------------------------
# Secrets: user-assigned identity for the Container App.
# NOTE: Key Vault was tried here but this tenant's policy forces
# publicNetworkAccess=Disabled on new vaults, which blocks Terraform's own
# secret writes from outside a private endpoint. The master key is instead a
# native Container Apps secret (still encrypted at rest by the platform); the
# Foundry connection needs no secret at all since it uses managed identity.
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "litellm" {
  name                = "id-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# Grants LiteLLM's managed identity data-plane access to call the Foundry/Azure
# OpenAI account directly (no API key - the account enforces disableLocalAuth).
resource "azurerm_role_assignment" "litellm_cognitive_services_openai_user" {
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.litellm.principal_id
}

# Azure RBAC role assignments take time to propagate; give it a head start
# before the container app starts and tries to use it.
resource "time_sleep" "wait_for_rbac" {
  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.litellm_cognitive_services_openai_user,
  ]
}

resource "random_password" "litellm_master_key" {
  length  = 40
  special = false
}

# Container Apps reduces `$$` to `$` while expanding container environment
# variables. Escape each literal dollar sign in the stored secret so the
# process receives exactly the password supplied by the operator.
locals {
  litellm_ui_password_container_value = replace(var.litellm_ui_password, "$", "$$")
}

# ---------------------------------------------------------------------------
# LiteLLM Container App
# ---------------------------------------------------------------------------

resource "azurerm_container_app" "litellm" {
  name                         = "ca-${var.project_name}"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.litellm.id]
  }

  secret {
    name  = "litellm-master-key"
    value = "sk-${random_password.litellm_master_key.result}"
  }

  secret {
    name  = "database-url"
    value = local.litellm_database_url
  }

  secret {
    name  = "redis-password"
    value = azurerm_managed_redis.litellm.default_database[0].primary_access_key
  }

  secret {
    name  = "litellm-ui-password-escaped"
    value = var.litellm_ui_password != "" ? local.litellm_ui_password_container_value : "not-yet-configured"
  }

  template {
    min_replicas = var.litellm_min_replicas
    max_replicas = var.litellm_max_replicas

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = var.litellm_scale_concurrent_requests
    }

    container {
      name   = "litellm"
      image  = var.litellm_image
      cpu    = var.litellm_container_cpu
      memory = var.litellm_container_memory

      # No Azure Files mount: this tenant blocks storage-account key auth, so
      # the config.yaml content is written to local disk at container start.
      command = ["/bin/sh", "-c"]
      args = [
        "echo \"$LITELLM_CONFIG_CONTENT\" > /tmp/litellm-config.yaml && exec litellm --config /tmp/litellm-config.yaml"
      ]

      env {
        name = "LITELLM_CONFIG_CONTENT"
        value = templatefile("${path.module}/files/litellm-config.yaml.tftpl", {
          model_alias     = var.litellm_model_alias
          deployment_name = var.azure_openai_deployment_name
        })
      }

      env {
        name  = "AZURE_API_BASE"
        value = var.azure_openai_endpoint
      }

      env {
        name  = "AZURE_API_VERSION"
        value = var.azure_openai_api_version
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.litellm.client_id
      }

      env {
        name        = "LITELLM_MASTER_KEY"
        secret_name = "litellm-master-key"
      }

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
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
        name        = "REDIS_PASSWORD"
        secret_name = "redis-password"
      }

      env {
        name  = "REDIS_SSL"
        value = "True"
      }

      env {
        name  = "UI_USERNAME"
        value = var.litellm_ui_username
      }

      # Login redirects must target Front Door, not the blocked origin hostname.
      env {
        name  = "PROXY_BASE_URL"
        value = "https://${azurerm_cdn_frontdoor_endpoint.litellm_admin.host_name}"
      }

      env {
        name        = "UI_PASSWORD"
        # Changing the reference creates a revision that loads the corrected secret.
        secret_name = "litellm-ui-password-escaped"
      }

      # No custom HTTP probes: Container Apps' default TCP probe is more
      # forgiving. A tight 1s HTTP readiness timeout + successThreshold=3 kept
      # the revision stuck "Activating" and unreachable externally, even
      # though the app itself was healthy (confirmed via internal logs).
    }
  }

  ingress {
    external_enabled = true
    target_port      = 4000
    transport        = "auto"

    dynamic "ip_security_restriction" {
      for_each = toset(data.azurerm_network_service_tags.frontdoor_backend.ipv4_cidrs)
      content {
        name             = "fd-${replace(replace(ip_security_restriction.value, "/", "-"), ":", "_")}"
        action           = "Allow"
        ip_address_range = ip_security_restriction.value
        description      = "Azure Front Door backend pool"
      }
    }

    ip_security_restriction {
      name             = "vnet-internal"
      action           = "Allow"
      ip_address_range = tolist(azurerm_virtual_network.main.address_space)[0]
      description      = "In-VNet callers (e.g. chat-client2's direct calls to LiteLLM, not routed through Front Door)"
    }

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    time_sleep.wait_for_rbac,
    azurerm_private_endpoint.redis,
    azurerm_private_dns_zone_virtual_network_link.redis,
  ]
}
