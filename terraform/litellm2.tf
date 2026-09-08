# ---------------------------------------------------------------------------
# Scenario 2: no Entra ID sign-in on the client side.
#   chat-client2 --(LiteLLM master key)--> LiteLLM2 --(managed identity)--> Foundry
#
# The Foundry account (fdry-litellm-vemyrs) enforces disableLocalAuth=true via
# tenant policy (confirmed permanent - blocks API keys tenant-wide regardless
# of resource kind), so the LiteLLM2 -> Foundry leg uses the same managed-
# identity pattern as the first LiteLLM instance. The chat-client2 -> LiteLLM2
# leg stays access-key/master-key based - that contrast (no end-user sign-in)
# is what this scenario actually demonstrates.
# ---------------------------------------------------------------------------

resource "random_password" "litellm2_master_key" {
  length  = 40
  special = false
}

resource "azurerm_container_app" "litellm2" {
  name                         = "ca-${var.project_name}2"
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
    value = "sk-${random_password.litellm2_master_key.result}"
  }

  secret {
    name  = "database-url"
    value = local.litellm_database_url
  }

  secret {
    name  = "litellm-ui-password"
    value = var.litellm_ui_password != "" ? var.litellm_ui_password : "not-yet-configured"
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

      command = ["/bin/sh", "-c"]
      args = [
        "echo \"$LITELLM_CONFIG_CONTENT\" > /tmp/litellm-config.yaml && exec litellm --config /tmp/litellm-config.yaml"
      ]

      env {
        name = "LITELLM_CONFIG_CONTENT"
        value = templatefile("${path.module}/files/litellm2-config.yaml.tftpl", {
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
        name  = "UI_USERNAME"
        value = var.litellm_ui_username
      }

      env {
        name        = "UI_PASSWORD"
        secret_name = "litellm-ui-password"
      }
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

  depends_on = [time_sleep.wait_for_rbac]
}

# ---------------------------------------------------------------------------
# chat-client2: uses the shared App Service Plan (azurerm_service_plan.chat_client), no Entra ID / auth at all.
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "chat_client2" {
  name                = var.chat_client2_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.chat_client.location
  service_plan_id     = azurerm_service_plan.chat_client.id
  https_only          = true
  # FTP/WebDeploy basic auth are separate credential channels not covered by
  # the ip_restriction below (that only governs the main site) - keep both
  # disabled so they can't bypass the Front-Door-only access model.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  # Standard Front Door can't reach a Private-Link-only origin, so public
  # access is back on here but locked to this Front Door profile only - see
  # frontdoor.tf. virtual_network_subnet_id (outbound) and the Private
  # Endpoint (inbound, for in-VNet callers) from the VNet retrofit are unaffected.
  public_network_access_enabled = true
  virtual_network_subnet_id     = azurerm_subnet.appsvc.id
  tags                          = var.tags

  site_config {
    application_stack {
      dotnet_version = "10.0"
    }
    minimum_tls_version           = "1.2"
    ip_restriction_default_action = "Deny"

    ip_restriction {
      action      = "Allow"
      name        = "AllowAzureFrontDoorOnly"
      priority    = 100
      service_tag = "AzureFrontDoor.Backend"

      headers {
        x_azure_fdid = [azurerm_cdn_frontdoor_profile.main.resource_guid]
      }
    }
  }

  app_settings = {
    # Use the same public, governed entry point used to manage LiteLLM2.
    "LiteLLm__BaseUrl" = "https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}"
    "LiteLLm__ApiKey"  = "sk-${random_password.litellm2_master_key.result}"
    "LiteLLm__Model"   = var.litellm_model_alias
  }
}

resource "azurerm_private_endpoint" "chat_client2" {
  name                = "pe-${var.chat_client2_app_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.chat_client2_app_name}"
    private_connection_resource_id = azurerm_linux_web_app.chat_client2.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "appsvc-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.app_service.id]
  }
}

output "litellm2_url" {
  description = "Public URL of the second LiteLLM proxy through Azure Front Door. The direct Container Apps origin is IP-restricted."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}"
}

output "litellm2_master_key" {
  description = "Bearer token for calling the second LiteLLM proxy."
  value       = "sk-${random_password.litellm2_master_key.result}"
  sensitive   = true
}

output "chat_client2_url" {
  description = "Public URL of the second (access-key only, no Entra ID) chat client through Azure Front Door."
  value       = "https://${azurerm_cdn_frontdoor_endpoint.chat_client2.host_name}"
}
