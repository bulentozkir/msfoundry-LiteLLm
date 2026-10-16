# Public APIM AI Gateway + private Microsoft Foundry

This isolated Terraform root deploys only:

- one resource group
- API Management in the `AIGateway` preview pricing tier
- one Microsoft Foundry `AIServices` account with exactly three model deployments
- account-scoped Foundry User access for the gateway's managed identity
- the Foundry provider connection, three gateway model registrations and aliases,
  and three independent gateway runtime keys
- one shared VNet, three dedicated subnets, supporting NSGs, one Foundry private
  endpoint, and three private DNS zones linked to the shared VNet

It does not deploy App Service, App Service plans, per-user model deployments,
LiteLLM, MLflow, databases, Redis, storage accounts, monitoring, agents, or projects.
Other Terraform roots and existing client configurations are not used or changed.

## Target and models

| Setting | Value |
| --- | --- |
| Entra tenant | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
| Subscription | `fb7dfa70-78b9-4e56-8d2d-fa2eff765241` |
| Resource group | `rg-foundry-aigateway-sweden` |
| Region | Sweden Central |

| Deployment / gateway alias | Catalog model | Version | Global Standard capacity |
| --- | --- | --- | --- |
| `Gpt5.4mini` | `gpt-5.4-mini` | `2026-03-17` | 1 |
| `Phi` | `Phi-4` | `7` | 1 |
| `FW-DeepSeek-V4.1-Flash` | `DeepSeek-V4-Flash` | `2026-04-23` | 250 |

The DeepSeek deployment name is an alias for the catalog model shown above, not
a separate model version. All three deployments disable automatic version
upgrades. Quota and regional availability must be checked before applying.

Foundry local authentication and public network access are disabled. The gateway
uses its system-assigned managed identity to invoke Foundry privately; clients
reach the public gateway over HTTPS and authenticate with a gateway runtime key.

## Shared VNet and traffic flow

`internet client -> public AI Gateway -> shared VNet -> Foundry private endpoint`

The shared VNet is `10.42.0.0/16` in Sweden Central:

| Subnet | Address range | Purpose / delegation |
| --- | --- | --- |
| `snet-foundry-inbound` | `10.42.0.0/24` | Foundry private endpoint |
| `snet-foundry-outbound` | `10.42.1.0/24` | Foundry outbound injection; `Microsoft.App/environments` |
| `snet-aigw-outbound` | `10.42.2.0/24` | AI Gateway outbound integration; `Microsoft.Web/serverFarms` |

A fourth gateway-inbound subnet/private endpoint is unnecessary because clients
reach the gateway from the internet. Its outbound NSG permits HTTPS to Foundry
and the required Storage and Azure Key Vault platform dependencies; those service
tags do not create storage accounts or vaults.

The Foundry private-endpoint subnet permits HTTPS from the gateway and Foundry
outbound subnets and denies other inbound traffic. Private DNS zones
`privatelink.services.ai.azure.com`, `privatelink.openai.azure.com`, and
`privatelink.cognitiveservices.azure.com` resolve the Foundry hostnames privately.
Keep using the normal Foundry hostname, not a private-link hostname or IP address.

Foundry outbound injection is configured when the account is created. It applies
to supported agent/evaluation workloads, not to the placement of the model
hosting infrastructure. No such workloads are deployed here. Injection routes
supported outbound traffic into the VNet but is not an internet-egress firewall;
no firewall, NAT gateway, or unrestricted-outbound-isolation claim is included.

## Three access keys and preview limitation

Terraform creates runtime keys named `gpt5-4mini`, `phi`, and
`fw-deepseek-v4-1-flash`, so clients can manage and rotate them independently.

**AI Gateway preview keys are gateway-scoped: each key can access all three
published models. They are not model-isolated APIM subscriptions.** The
`AIGateway` preview pricing tier does not currently support per-asset key scoping.
The key names express intended usage only; they do not enforce authorization.
See [runtime access keys](https://learn.microsoft.com/azure/api-management/ai-gateway-govern-secure-assets#runtime-access-keys).
No monthly budget or application-specific cost policy is installed.

## Deploy

Use only this directory and a newly reviewed full plan, not the parent Terraform
root or historical saved plans:

```powershell
az login --tenant 16b3c013-d300-468d-ac64-7eda0820b6d3
az account set --subscription fb7dfa70-78b9-4e56-8d2d-fa2eff765241
Set-Location .\terraform\apim-only
terraform init
terraform fmt -check
terraform validate
terraform test
terraform plan -out=tfplan
terraform apply tfplan
```

The `Microsoft.ApiManagement`, `Microsoft.CognitiveServices`, `Microsoft.Network`,
`Microsoft.App`, and `Microsoft.Web` resource providers must already be registered.
Automatic provider registration is disabled to avoid registering unrelated
services.

Review the plan before applying: it must contain only the resources listed above
and local Terraform random/timing helpers. If an earlier deployment still has an
application, extra models, or application-specific keys, this simplified
configuration would remove them; do not apply such a destructive plan without
separate approval.

## Endpoints and runtime key

- `terraform output -raw ai_gateway_base_url` returns the OpenAI-compatible URL.
- AI Gateway portal: <https://ai.gateway.azure.com>
- `terraform output model_deployments` lists the three client-facing aliases.
- `terraform output subnet_ids` lists the three dedicated shared-VNet subnets.

Read the sensitive key into memory rather than writing it into source or logs:

```powershell
$keys = terraform output -json model_access_keys | ConvertFrom-Json
$gatewayKey = $keys.Phi
```

Terraform state and saved plans can contain secrets even when outputs are marked
sensitive. Keep them protected and out of version control.
