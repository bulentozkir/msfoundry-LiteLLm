# LiteLLM + Chat App2

This isolated Terraform root adds a LiteLLM Container App and the existing
`chat-client2` application alongside the working APIM architecture. The resource
group, Foundry account, and free Linux App Service plan are read-only data sources.
Do not apply the legacy Terraform root to deploy this test setup.

## Live endpoints

Verified on 2026-09-21:

- Mini chat: <https://foundry-chat2-8ps1sz.azurewebsites.net/chat2>
- Phi chat: <https://foundry-chat2-8ps1sz.azurewebsites.net/chatphi>
- DeepSeek chat: <https://foundry-chat2-8ps1sz.azurewebsites.net/chatdeepseek>
- Protected proxy:
  <https://ca-litellm-8ps1sz.livelypebble-18eb5748.swedencentral.azurecontainerapps.io>

Both chat pages passed browser submission tests. All three proxy model routes
returned HTTP 200, anonymous inference returned HTTP 401, and the post-deployment
Terraform plan reported no pending changes.

## Resources

- `ca-litellm-8ps1sz`: LiteLLM v1.101.0, pinned by digest, one worker, 1 vCPU /
  2 GiB, Consumption scale 0-1.
- `cae-litellm-8ps1sz`: Container Apps Consumption environment.
- `log-litellm-8ps1sz`: 30-day logs with a 0.1 GB daily ingestion cap.
- `id-litellm-8ps1sz`: managed identity with Foundry User at the existing account.
- `foundry-chat2-8ps1sz`: .NET 10 chat app on `asp-chat3-8ps1sz` (F1).
- `psql-litellm-8ps1sz`: PostgreSQL 16 Flexible Server, B1ms (1 vCore / 2 GiB),
  32 GiB storage, seven-day backups, no HA or storage autogrow; database `litellm`.
- `redis-litellm-8ps1sz`: Azure Managed Redis Balanced B0 (0.5 GB), no HA,
  encrypted nonclustered connections, database 0, `NoEviction` policy.

LiteLLM exposes `gpt-5.4-mini`, `phi-4`, and `FW-DeepSeek-V4.1-Flash`. The existing
app2 Mini, Phi, and DeepSeek pages call LiteLLM's OpenAI-compatible API. Its legacy
`Mlflow:*` setting names are retained for compatibility; no MLflow server or Basic
Auth credentials are configured. The proxy master key is generated, stored in
Container Apps secrets and server-side App Service settings, and marked sensitive
in Terraform outputs. State and plan files must remain private and uncommitted.

## Operations

Use the `chat_app2_url` output for the Mini chat page, `/chatphi` for Phi, and
`/chatdeepseek` for DeepSeek. The `litellm_url` output is the protected proxy endpoint. Publish
`chat-client2` in Release mode and deploy the package to `chat_app2_name` using
Microsoft Entra authentication, without enabling SCM or FTP basic authentication.

## PostgreSQL and Managed Redis

The dedicated LiteLLM managed identity authenticates to both datastores. It is
the PostgreSQL server's Entra administrator so it can initialize the LiteLLM
schema, and it has a Managed Redis access-policy assignment on the dedicated
cache. PostgreSQL password authentication and Redis access keys are disabled.
The pinned LiteLLM release refreshes the short-lived identity tokens.

`postgres_allowed_ip_addresses` is a required explicit firewall allowlist. The
local, git-ignored `postgres-egress.auto.tfvars.json` holds the current Container
App outbound IPs. Refresh and compare this list before applying; there is no
allow-all-Azure firewall rule. Keep each entry a single IPv4 address.

The current Container Apps environment has no VNet integration. This increment
preserves its URL and uses public datastore endpoints with TLS and identity
authentication. Managed Redis has no IP firewall support; Private Link requires
a separately planned VNet migration. PostgreSQL additionally restricts connections
to the supplied egress IPs. Do not silently widen the allowlist on connection errors.

LiteLLM initializes schema migrations on startup and fails startup if migrations
fail. Its database connection pool is limited to five connections. A separate
persistent `LITELLM_SALT_KEY` is stored as a Container Apps secret; do not rotate
or lose it after database-stored credentials exist. The existing master key is
unchanged. The admin UI at `/ui/` uses `admin` and the master key for bootstrap
login; create individual admin accounts for ongoing administrative access.

PostgreSQL enables persistent users, virtual keys, model settings, and spend
records. Prompt/response storage in spend logs is explicitly disabled. Redis
supports shared auth/router state; LLM response caching is opt-in (`default_off`)
to preserve the existing chat behavior. Verify it using authenticated `/cache/ping`.

This is a no-sign-in test app, not a multi-user production gateway. The shared F1
plan has CPU/memory limits, and both app and proxy can cold-start. Requests have
a 120-second client timeout. B1ms and non-HA B0 are small test configurations,
not production availability guarantees. Token metrics remain available on the
Foundry resource in Azure Monitor.

PostgreSQL and Managed Redis are billed while provisioned, even when LiteLLM
scales to zero. Container Apps compute, log ingestion, and Foundry tokens also
incur usage charges.
The Log Analytics ingestion cap is not a billing budget. The APIM monthly budget
does not cover calls made directly from LiteLLM to Foundry. No APIM policies,
model capacities, per-user deployments, or Foundry authentication settings are
changed by this root.