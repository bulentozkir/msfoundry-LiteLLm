# ---------------------------------------------------------------------------
# App Service Plan shared by the chat client app(s) (see litellm2.tf for
# chat-client2, the only remaining chat client).
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "chat_client" {
  name                = "asp-${var.project_name}-chat-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}
