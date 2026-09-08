# ---------------------------------------------------------------------------
# Private Endpoint into the Foundry account (created outside Terraform via az
# cli - see session notes). Existing role-assignment/managed-identity auth is
# unaffected; this only changes the network path.
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "foundry" {
  name                = "pe-foundry-${var.project_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-foundry"
    private_connection_resource_id = var.foundry_account_id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "foundry-dns-zone-group"
    private_dns_zone_ids = [for z in azurerm_private_dns_zone.foundry : z.id]
  }
}

# The Foundry account itself is managed out-of-band (az cli), so its
# publicNetworkAccess flag is flipped here rather than via a Terraform
# resource attribute. Runs only after the private endpoint (+ DNS) exist, so
# there's no window where the account is unreachable by anything.
resource "null_resource" "foundry_disable_public_access" {
  triggers = {
    foundry_account_id = var.foundry_account_id
    private_endpoint_id = azurerm_private_endpoint.foundry.id
  }

  provisioner "local-exec" {
    command     = "az resource update --ids \"${var.foundry_account_id}\" --set properties.publicNetworkAccess=Disabled -o none"
    interpreter = ["pwsh", "-Command"]
  }

  depends_on = [
    azurerm_private_endpoint.foundry,
    azurerm_private_dns_zone_virtual_network_link.foundry,
  ]
}
