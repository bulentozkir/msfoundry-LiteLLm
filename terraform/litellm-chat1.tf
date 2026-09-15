# ---------------------------------------------------------------------------
# Chat1 web app (LiteLLM-backed).
#
# This shared root does not deploy LiteLLM itself. It wires chat1 to an
# externally deployed LiteLLM endpoint (for example standalone-litellm) via
# litellm_chat1_base_url and optional litellm_chat1_api_key.
# ---------------------------------------------------------------------------

locals {
  chat1_litellm_base_url = trimsuffix(var.litellm_chat1_base_url, "/")
}

resource "azurerm_linux_web_app" "chat_client1" {
  name                                           = var.chat_client1_app_name
  resource_group_name                            = azurerm_resource_group.main.name
  location                                       = azurerm_service_plan.chat_client.location
  service_plan_id                                = azurerm_service_plan.chat_client.id
  https_only                                     = true
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
    "LiteLLm__BaseUrl"  = local.chat1_litellm_base_url
    "LiteLLm__ApiKey"   = var.litellm_chat1_api_key
    "LiteLLm__Model"    = var.litellm_chat1_model_alias
    "LiteLLm__PhiModel" = var.litellm_chat1_phi_model_alias
  }
}

resource "azurerm_private_endpoint" "chat_client1" {
  name                = "pe-${var.chat_client1_app_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.chat_client1_app_name}"
    private_connection_resource_id = azurerm_linux_web_app.chat_client1.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "appsvc-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.app_service.id]
  }
}