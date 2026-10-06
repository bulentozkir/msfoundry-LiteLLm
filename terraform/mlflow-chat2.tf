# ---------------------------------------------------------------------------
# App Service plan plus chat2 web app resources.
# chat1 (LiteLLM-backed) resources are in litellm-chat1.tf.
# chat3 (APIM-backed) resources are in apim-chat3.tf.
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
  # the main-site access settings, so keep both disabled.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  # Retain both direct public access and the existing private endpoint.
  public_network_access_enabled = true
  virtual_network_subnet_id     = azurerm_subnet.appsvc.id
  tags                          = var.tags

  site_config {
    application_stack {
      dotnet_version = "10.0"
    }
    minimum_tls_version           = "1.2"
    ip_restriction_default_action = "Allow"
  }

  app_settings = {
    # The VNet-integrated app calls the Container Apps origin directly.
    "Mlflow__BaseUrl"  = "https://${azurerm_container_app.mlflow_gateway.ingress[0].fqdn}/gateway/mlflow/v1"
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

