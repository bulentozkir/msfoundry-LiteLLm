# MLflow deployment packages

## Customer-deployable platform (standalone-mlflow)

[standalone-mlflow/mlflow.md](standalone-mlflow/mlflow.md) explains the independent Terraform package, five-value setup, admin operations, native PostgreSQL automatic backups/PITR, and staged upgrades/rollback.

**Naming note:** this package was renamed from `standalone-litellm` as part of moving the repo off LiteLLM (its paid tier gates features like Entra ID integration). The folder/file names now say MLflow, but its Terraform module and admin script still deploy a **LiteLLM** container internally - porting the module itself to MLflow's gateway architecture (Postgres-backed REST API, no virtual-key/budget model) is a separate, larger task, not yet done. Do not treat this package as already running MLflow.

The standalone package creates only the proxy container, Container Apps, private PostgreSQL, Managed Redis and their supporting network/identity/logging resources. It has **no dependency on App Service, Front Door, Foundry or the chat application**. Deploy it as its own root/state or call its child module from a customer-owned root.

## Existing demonstration stack (separate)

| Files | Responsibility |
|---|---|
| [terraform/chat-client.tf](terraform/chat-client.tf) | App Service Plan, chat app and its private endpoint |
| [terraform/frontdoor.tf](terraform/frontdoor.tf) | Front Door profile, endpoints, origins, routes and redirect rules |
| [terraform/foundry-private-link.tf](terraform/foundry-private-link.tf) | Foundry private connectivity |
| [terraform/mlflow-gateway-app.tf](terraform/mlflow-gateway-app.tf), [terraform/mlflow-gateway.tf](terraform/mlflow-gateway.tf) | MLflow AI Gateway Container App (replaces the former LiteLLM2 proxy in-place) |
| [terraform/postgres.tf](terraform/postgres.tf), [terraform/storage.tf](terraform/storage.tf) | Existing demonstration backing services (Postgres backend store, Storage Account artifact store; no Redis) |
| [terraform/main.tf](terraform/main.tf), [terraform/networking.tf](terraform/networking.tf) | Existing demonstration shared infrastructure |

File separation inside the existing `terraform` directory does **not** create separate states: Terraform loads that entire directory as one root. That stack retains its existing integrations. The standalone directory is independent; this change does not migrate or deploy any existing Azure resource. Do not apply the standalone package against the demo's state.