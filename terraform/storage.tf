# ---------------------------------------------------------------------------
# Storage Account for the MLflow gateway's artifact store (wasbs://). No
# Redis anywhere in this stack anymore - Postgres is the only stateful
# dependency besides this. Access is managed-identity only: shared keys are
# disabled entirely (shared_access_key_enabled = false), so the only way in
# is Azure AD (Storage Blob Data Contributor on the reused identity) - same
# no-API-keys model as the rest of this deployment. Private endpoint only;
# no public network access.
#
# Caveat: MLflow's Azure Blob artifact repo falls back to DefaultAzureCredential
# only when neither AZURE_STORAGE_CONNECTION_STRING nor AZURE_STORAGE_ACCESS_KEY
# is set (confirmed via mlflow/store/artifact/azure_blob_artifact_repo.py) -
# both are intentionally left unset here. Its multipart-upload path still
# requires an account key (generate_blob_sas with account_key) and will fail
# under key-less auth; this only matters if large model artifacts are ever
# logged, not for the gateway's own use.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "mlflow" {
  name                     = "stmlflow${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  tags                     = var.tags

  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  shared_access_key_enabled        = false
  public_network_access_enabled    = false
  allow_nested_items_to_be_public  = false
  default_to_oauth_authentication  = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "mlflow_artifacts" {
  name                  = "mlflow-artifacts"
  storage_account_id    = azurerm_storage_account.mlflow.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "mlflow_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.mlflow.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.mlflow.principal_id
}

moved {
  from = azurerm_role_assignment.litellm_storage_blob_data_contributor
  to   = azurerm_role_assignment.mlflow_storage_blob_data_contributor
}

resource "time_sleep" "wait_for_storage_rbac" {
  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.mlflow_storage_blob_data_contributor,
  ]
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                = "link-storage-blob"
  private_dns_zone_id = azurerm_private_dns_zone.storage_blob.id
  virtual_network_id  = azurerm_virtual_network.main.id
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-blob-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-storage-blob"
    private_connection_resource_id = azurerm_storage_account.mlflow.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }
}

output "mlflow_artifact_root" {
  description = "wasbs:// artifact-store URI passed to mlflow server --default-artifact-root."
  value       = "wasbs://${azurerm_storage_container.mlflow_artifacts.name}@${azurerm_storage_account.mlflow.name}.blob.core.windows.net/"
}
