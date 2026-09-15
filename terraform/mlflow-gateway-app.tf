# ---------------------------------------------------------------------------
# MLflow AI Gateway now runs here, in-place, reusing the same Container App
# resource, name, identity, and Front Door route that the old LiteLLM proxy
# used - see mlflow-gateway.tf for the ACR/Postgres-database/RBAC and
# storage.tf for the artifact-store Storage Account this needs. LiteLLM, its
# master key, Redis and its admin-UI credentials are removed entirely; the
# chat-client2 -> gateway leg drops to no-auth (network-restricted by the
# same Front Door CIDR allowlist below), and the gateway -> Foundry leg still
# uses managed identity (see refresh_secrets.py sidecar).
# ---------------------------------------------------------------------------

moved {
  from = azurerm_container_app.litellm2
  to   = azurerm_container_app.mlflow_gateway
}

# Container Apps reduces `$$` to `$` while expanding container environment
# variables. Escape each literal dollar sign in the stored secret so the
# process receives exactly the password supplied by the operator.
locals {
  mlflow_admin_password_container_value = replace(var.mlflow_admin_password, "$", "$$")
}

resource "azurerm_container_app" "mlflow_gateway" {
  name                         = "ca-${var.project_name}2"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.mlflow.id]
  }

  registry {
    server   = azurerm_container_registry.mlflow.login_server
    identity = azurerm_user_assigned_identity.mlflow.id
  }

  secret {
    name  = "database-url"
    value = local.mlflow_database_url
  }

  secret {
    name  = "auth-database-url"
    value = local.mlflow_auth_database_url
  }

  secret {
    name  = "admin-password"
    value = local.mlflow_admin_password_container_value
  }

  secret {
    name  = "flask-secret-key"
    value = random_password.mlflow_flask_secret_key.result
  }

  template {
    min_replicas = var.mlflow_min_replicas
    max_replicas = 1

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = var.mlflow_scale_concurrent_requests
    }

    container {
      name    = "mlflow"
      image   = "${azurerm_container_registry.mlflow.login_server}/mlflow-gateway:latest"
      cpu     = var.mlflow_container_cpu
      memory  = var.mlflow_container_memory
      command = ["/bin/sh", "-c"]
      args = [
        # --workers defaults to 4; each worker loads the full mlflow[genai]
        # dependency set independently, which OOM-killed this container in a
        # crash loop at the previous 2Gi allocation.
        #
        # basic_auth.ini is generated here (not baked into the image) so the
        # admin username/password/auth-db can come from Container Apps secrets;
        # mlflow.server.auth's config.py only reads MLFLOW_AUTH_CONFIG_PATH, no
        # per-key env var overrides exist. --app-name basic-auth still wraps
        # the same create_fastapi_app() used by default (confirmed via source:
        # mlflow/server/auth/__init__.py's create_app() calls it when running
        # under uvicorn), so gateway_router stays mounted and protected.
        <<-EOT
        cat > /tmp/mlflow_basic_auth.ini <<INI_EOF
        [mlflow]
        default_permission = READ
        database_uri = $MLFLOW_AUTH_DATABASE_URL
        admin_username = $MLFLOW_ADMIN_USERNAME
        admin_password = $MLFLOW_ADMIN_PASSWORD
        authorization_function = mlflow.server.auth:authenticate_request_basic_auth
        INI_EOF
        exec mlflow server --host 0.0.0.0 --port 4000 --workers 2 --app-name basic-auth --backend-store-uri "$BACKEND_STORE_URI" --default-artifact-root "$ARTIFACT_ROOT"
        EOT
      ]

      env {
        name        = "BACKEND_STORE_URI"
        secret_name = "database-url"
      }
      env {
        name        = "MLFLOW_AUTH_DATABASE_URL"
        secret_name = "auth-database-url"
      }
      env {
        name  = "MLFLOW_AUTH_CONFIG_PATH"
        value = "/tmp/mlflow_basic_auth.ini"
      }
      env {
        name  = "MLFLOW_ADMIN_USERNAME"
        value = var.mlflow_admin_username
      }
      env {
        name        = "MLFLOW_ADMIN_PASSWORD"
        secret_name = "admin-password"
      }
      env {
        name        = "MLFLOW_FLASK_SERVER_SECRET_KEY"
        secret_name = "flask-secret-key"
      }
      # Covers gateway/artifact routes served natively by FastAPI, which have
      # no permission "validator" registered and would otherwise pass through
      # unauthenticated (see add_fastapi_permission_middleware's fail-closed
      # branch in mlflow/server/auth/__init__.py).
      env {
        name  = "MLFLOW_BASIC_AUTH_FAIL_CLOSED"
        value = "true"
      }
      env {
        name  = "ARTIFACT_ROOT"
        value = "wasbs://${azurerm_storage_container.mlflow_artifacts.name}@${azurerm_storage_account.mlflow.name}.blob.core.windows.net/"
      }
      env {
        name  = "MLFLOW_ENABLE_AI_GATEWAY"
        value = "true"
      }
      # Without this, mlflow's own DNS-rebinding guard 403s every request that
      # arrives via Front Door (its Host header isn't localhost/private-IP).
      # Setting this env var REPLACES mlflow's default allowlist rather than
      # extending it, so localhost must be listed explicitly too - otherwise
      # the refresh-secrets sidecar's own http://localhost:4000 calls 403.
      # mlflow's matcher is an EXACT string match unless the entry itself
      # contains "*" (see is_allowed_host_header/fnmatch in security_utils.py),
      # and the sidecar's Host header is "localhost:4000" (port included since
      # 4000 isn't the default http port) - so a bare "localhost" entry never
      # matches and every sidecar call 403s. Needs the ":*" wildcard variant,
      # matching what mlflow's own get_default_allowed_hosts() does.
      env {
        name  = "MLFLOW_SERVER_ALLOWED_HOSTS"
        value = "localhost,localhost:*,127.0.0.1,127.0.0.1:*,${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name},ca-${var.project_name}2.${azurerm_container_app_environment.main.default_domain}"
      }
      # The gateway UI's own same-origin fetch/XHR calls (e.g. the Usage tab)
      # send an Origin header and are state-changing (POST), so without this
      # mlflow's CORS guard 403s them as "cross-origin" even though they're
      # not - confirmed via a direct 403 "Cross-origin request blocked" test.
      # Must be scheme+host, no path (see is_localhost_origin/should_block_cors_request).
      env {
        name  = "MLFLOW_SERVER_CORS_ALLOWED_ORIGINS"
        value = "https://${azurerm_cdn_frontdoor_endpoint.litellm2_admin.host_name},https://ca-${var.project_name}2.${azurerm_container_app_environment.main.default_domain}"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.mlflow.client_id
      }
    }

    container {
      name    = "refresh-secrets"
      image   = "${azurerm_container_registry.mlflow.login_server}/mlflow-gateway:latest"
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["python", "/app/refresh_secrets.py"]

      env {
        name  = "MLFLOW_BASE_URL"
        value = "http://localhost:4000"
      }
      env {
        name  = "MLFLOW_ADMIN_USERNAME"
        value = var.mlflow_admin_username
      }
      env {
        name        = "MLFLOW_ADMIN_PASSWORD"
        secret_name = "admin-password"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.mlflow.client_id
      }
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = var.azure_openai_endpoint
      }
      env {
        name  = "AZURE_OPENAI_API_VERSION"
        value = var.azure_openai_api_version
      }
      env {
        name  = "MLFLOW_MODEL_MAP"
        value = local.mlflow_model_map
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 4000
    transport        = "auto"

    dynamic "ip_security_restriction" {
      for_each = toset(data.azurerm_network_service_tags.frontdoor_backend.ipv4_cidrs)
      content {
        name             = "fd-${replace(replace(ip_security_restriction.value, "/", "-"), ":", "_")}"
        action           = "Allow"
        ip_address_range = ip_security_restriction.value
        description      = "Azure Front Door backend pool"
      }
    }

    ip_security_restriction {
      name             = "vnet-internal"
      action           = "Allow"
      ip_address_range = tolist(azurerm_virtual_network.main.address_space)[0]
      description      = "In-VNet callers (e.g. chat-client2's direct calls to the gateway, not routed through Front Door)"
    }

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    time_sleep.wait_for_rbac,
    time_sleep.wait_for_acr_rbac,
    time_sleep.wait_for_storage_rbac,
    azurerm_role_assignment.mlflow_foundry_inference_user,
    azurerm_postgresql_flexible_server_database.mlflow,
    azurerm_postgresql_flexible_server_database.mlflow_auth,
    azurerm_private_endpoint.storage_blob,
  ]
}
