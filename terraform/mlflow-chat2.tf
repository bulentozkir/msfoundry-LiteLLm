# ---------------------------------------------------------------------------
# App Service plan plus chat2 web app resources.
# chat1 (LiteLLM-backed) resources are in litellm-chat1.tf.
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "chat_client" {
  name                = "asp-${var.project_name}-chat-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

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
    # Use the same public, governed entry point used to manage the gateway.
    "Mlflow__BaseUrl"  = "https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name}/gateway/mlflow/v1"
    "Mlflow__Model"    = var.mlflow_model_alias
    "Mlflow__PhiModel" = var.phi_model_alias
    # The gateway now requires HTTP Basic Auth (see mlflow-gateway-app.tf) -
    # App Service app_settings don't have Container Apps' "$$ -> $" quirk, so
    # this is passed through as-is, unlike the container's admin-password secret.
    "Mlflow__AdminUsername" = var.mlflow_admin_username
    "Mlflow__AdminPassword" = var.mlflow_admin_password
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

