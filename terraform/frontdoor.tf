# ---------------------------------------------------------------------------
# Azure Front Door Standard in front of chat1 and chat2. Standard tier cannot
# reach a Private-Link-only origin, so chat-client2's public network access
# is re-enabled (see mlflow-gateway-app.tf) and locked down to accept traffic only from
# this specific Front Door profile (service tag + X-Azure-FDID header check -
# the service tag alone is shared by every customer's Front Door, so the FDID
# header is what proves it's THIS profile). The Private Endpoint added in the
# VNet retrofit stays in place for any future in-VNet caller.
# ---------------------------------------------------------------------------

# Current published IP ranges for Front Door's backend pool - fetched live so
# this doesn't go stale (Microsoft rotates these). Container Apps ingress
# restrictions only support raw CIDR ranges, not service tags or header
# matching, so this is the closest equivalent available for that resource type.
data "azurerm_network_service_tags" "frontdoor_backend" {
  location = var.location
  service  = "AzureFrontDoor.Backend"
}

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "afd-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "chat_client2" {
  name                     = "fde-chat2-${random_string.suffix.result}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "chat_client2" {
  name                     = "og-chat-client2"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  health_probe {
    path                = "/"
    protocol            = "Https"
    request_type        = "HEAD"
    interval_in_seconds = 100
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "chat_client2" {
  name                          = "origin-chat-client2"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.chat_client2.id

  host_name                      = azurerm_linux_web_app.chat_client2.default_hostname
  origin_host_header             = azurerm_linux_web_app.chat_client2.default_hostname
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "chat_client2" {
  name                          = "route-chat-client2"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.chat_client2.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.chat_client2.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.chat_client2.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

resource "azurerm_cdn_frontdoor_endpoint" "chat_client1" {
  name                     = "fde-chat1-${random_string.suffix.result}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "chat_client1" {
  name                     = "og-chat-client1"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  health_probe {
    path                = "/"
    protocol            = "Https"
    request_type        = "HEAD"
    interval_in_seconds = 100
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "chat_client1" {
  name                          = "origin-chat-client1"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.chat_client1.id

  host_name                      = azurerm_linux_web_app.chat_client1.default_hostname
  origin_host_header             = azurerm_linux_web_app.chat_client1.default_hostname
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "chat_client1" {
  name                          = "route-chat-client1"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.chat_client1.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.chat_client1.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.chat_client1.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

# ---------------------------------------------------------------------------
# MLflow gateway UI/API access, at the user's explicit request.
# Container Apps ingress is public again (see mlflow-gateway-app.tf) and locked
# to Front Door's IP ranges via ip_security_restriction - weaker than the
# chat-client2 pattern (no header-based double-check is possible here), so
# this is a real, accepted tradeoff, not equivalent security. Unlike the old
# LiteLLM admin UI, there is no username/password layer on top of this -
# anyone who can reach the Front Door hostname can reach the gateway.
# ---------------------------------------------------------------------------

resource "azurerm_cdn_frontdoor_endpoint" "litellm2_admin" {
  name                     = "fde-litellm2-${random_string.suffix.result}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "litellm2" {
  name                     = "og-litellm2"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  health_probe {
    path                = "/health"
    protocol            = "Https"
    request_type        = "GET"
    interval_in_seconds = 30
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "litellm2" {
  name                          = "origin-litellm2"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.litellm2.id

  host_name                      = azurerm_container_app.mlflow_gateway.ingress[0].fqdn
  origin_host_header             = azurerm_container_app.mlflow_gateway.ingress[0].fqdn
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "litellm2" {
  name                          = "route-litellm2"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.litellm2_admin.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.litellm2.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.litellm2.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
}

