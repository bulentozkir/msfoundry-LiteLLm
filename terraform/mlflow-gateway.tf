# ---------------------------------------------------------------------------
# MLflow AI Gateway: runs inside the existing ca-litellm2 Container App (see
# mlflow-gateway-app.tf, renamed to azurerm_container_app.mlflow_gateway via a
# moved block) - same identity, same Front Door route, LiteLLM removed entirely.
# Only the ACR, the gateway's own Postgres database, and ACR-pull RBAC are
# new resources.
#
# Auth model: MLflow's Azure OpenAI provider only accepts a static
# "openai_api_key" secret value (no token-provider callback like LiteLLM's
# enable_azure_ad_token_refresh - confirmed via mlflow/gateway/providers/
# openai.py). When openai_api_type="azuread" that value is sent as
# "Authorization: Bearer <value>" - the correct shape for a live Azure AD
# access token, which is what this tenant's disableLocalAuth policy requires
# instead of an API key. The refresh_secrets.py sidecar mints a fresh token
# via the reused managed identity and PATCHes it into MLflow's gateway
# secret store on a loop; there is no other way to keep this fresh since
# MLflow does not read a callback at request time.
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "mlflow" {
  name                = "acrmlflow${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "mlflow_acr_pull" {
  scope                = azurerm_container_registry.mlflow.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.mlflow.principal_id
}

moved {
  from = azurerm_role_assignment.litellm_acr_pull
  to   = azurerm_role_assignment.mlflow_acr_pull
}

resource "time_sleep" "wait_for_acr_rbac" {
  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.mlflow_acr_pull,
  ]
}

# Static key required by mlflow.server.auth for CSRF/session signing - must
# stay constant across workers/restarts (see mlflow-gateway-app.tf).
resource "random_password" "mlflow_flask_secret_key" {
  length  = 48
  special = false
}

resource "azurerm_postgresql_flexible_server_database" "mlflow" {
  name      = "mlflow"
  server_id = azurerm_postgresql_flexible_server.mlflow.id
}

# Separate database for mlflow.server.auth's user/password store (basic-auth
# plugin - see mlflow-gateway-app.tf) - keeps auth data out of the tracking
# store and lets it persist across container restarts (unlike its sqlite default).
resource "azurerm_postgresql_flexible_server_database" "mlflow_auth" {
  name      = "mlflow_auth"
  server_id = azurerm_postgresql_flexible_server.mlflow.id
}

locals {
  mlflow_database_url      = "postgresql://${azurerm_postgresql_flexible_server.mlflow.administrator_login}:${random_password.postgres_admin_password.result}@${azurerm_postgresql_flexible_server.mlflow.fqdn}:5432/${azurerm_postgresql_flexible_server_database.mlflow.name}?sslmode=require"
  mlflow_auth_database_url = "postgresql://${azurerm_postgresql_flexible_server.mlflow.administrator_login}:${random_password.postgres_admin_password.result}@${azurerm_postgresql_flexible_server.mlflow.fqdn}:5432/${azurerm_postgresql_flexible_server_database.mlflow_auth.name}?sslmode=require"
  # deployment_name:model_definition_name:endpoint_name triples for the sidecar.
  mlflow_model_map = "${var.azure_openai_deployment_name}:mini-def:${var.mlflow_model_alias};${azurerm_cognitive_deployment.phi.name}:phi-def:${var.phi_model_alias}"
}

output "mlflow_acr_login_server" {
  value = azurerm_container_registry.mlflow.login_server
}
