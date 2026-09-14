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
  # already declined for cost). The MLflow gateway's ingress is locked down
  # to Front Door's published IP ranges via ip_security_restriction in mlflow-gateway-app.tf -
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

resource "azurerm_user_assigned_identity" "mlflow" {
  name                = "id-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

moved {
  from = azurerm_user_assigned_identity.litellm
  to   = azurerm_user_assigned_identity.mlflow
}

# Grants the gateway's managed identity data-plane access to call the Foundry/Azure
# OpenAI account directly (no API key - the account enforces disableLocalAuth).
resource "azurerm_role_assignment" "mlflow_cognitive_services_openai_user" {
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.mlflow.principal_id
}

moved {
  from = azurerm_role_assignment.litellm_cognitive_services_openai_user
  to   = azurerm_role_assignment.mlflow_cognitive_services_openai_user
}

# Azure RBAC role assignments take time to propagate; give it a head start
# before the container app starts and tries to use it.
resource "time_sleep" "wait_for_rbac" {
  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.mlflow_cognitive_services_openai_user,
  ]
}

