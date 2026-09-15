# ---------------------------------------------------------------------------
# Chat3 web app that calls APIM Developer.
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "chat_client3" {
  name                = var.chat_client3_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.chat_client.location
  service_plan_id     = azurerm_service_plan.chat_client.id
  https_only          = true

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = true
  virtual_network_subnet_id                      = azurerm_subnet.appsvc.id
  tags                                           = var.tags

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
    "Apim__BaseUrl"  = "${trimsuffix(azurerm_api_management.chat3.gateway_url, "/")}/${azurerm_api_management_api.chat3_foundry.path}"
    "Apim__Model"    = var.mlflow_model_alias
    "Apim__PhiModel" = var.phi_model_alias
  }
}

resource "azurerm_private_endpoint" "chat_client3" {
  name                = "pe-${var.chat_client3_app_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.chat_client3_app_name}"
    private_connection_resource_id = azurerm_linux_web_app.chat_client3.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "appsvc-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.app_service.id]
  }
}
