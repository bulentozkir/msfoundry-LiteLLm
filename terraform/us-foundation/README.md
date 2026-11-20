# East US 2 Foundry foundation

This root manages the private Foundry account and project, model deployments,
VNet, subnets, network security groups, private endpoint, and private DNS.
The existing `rg-foundry-aigateway` resource group is read, not managed by
Terraform. The dedicated gateway is owned by the independent
[US AI Gateway root](../us-ai-gateway/README.md).

Foundry public networking and local authentication are disabled. The gateway
uses its managed identity to connect through the private endpoint. The active
foundation deploys DeepSeek, Moonshot Kimi K3.1 Pro, legacy Fireworks Kimi K3,
GPT-6 Astra, and Claude Opus 5.5. DeepSeek's default capacity is 250.
Applying the Claude deployment accepts the
Anthropic Marketplace terms using the real organization attestation supplied
in `claude_provider_data`.

The local state and saved plans can contain attestation data. Restrict access
to them, supply the real variable through a protected process environment or
an access-controlled ignored variable file, and never commit it. Plans that
change a Claude deployment can display the attestation, so restrict terminal
and log access as well.
The gateway consumes the nonsecret `gateway_foundation` output, but access
to Terraform remote state permits reading the complete snapshot.

From the repository root in PowerShell, after supplying the required
attestation variable:

```powershell
terraform -chdir=terraform\us-foundation init
terraform -chdir=terraform\us-foundation fmt -check
terraform -chdir=terraform\us-foundation validate
terraform -chdir=terraform\us-foundation test
terraform -chdir=terraform\us-foundation plan -out=reviewed.tfplan
```

Review the plan, quota, cost, and networking before applying it. After adding
a deployment, review a separate gateway plan to register it. When retiring a
deployment, remove its gateway aliases and registrations before deleting the
Foundry deployment, then reconcile the gateway state. Capacity-only
updates do not require new gateway registrations or credential changes.

Apply the reviewed foundation plan with one concurrent operation:

```powershell
terraform -chdir=terraform\us-foundation apply -parallelism=1 reviewed.tfplan
```

Azure serializes model updates under the Foundry account. Parallel updates
can fail with HTTP 409 `RequestConflict` even when their quotas are separate.
After a partial apply, wait for the account and deployments to finish their
current operations, generate and review a fresh plan, then apply serially.
Do not reuse the stale saved plan.

## Maximum approved model capacities

The following `GlobalStandard` allocations were verified on November 12, 2026
for the original deployments and November 20, 2026 for Kimi K3.1 Pro:

| Deployment | Capacity units | Tokens/minute | Requests/minute |
|---|---:|---:|---:|
| `FW-DeepSeek-V4.1-Flash` | 250 | 250,000 | 250 |
| `FW-Kimi-K3` | 500 | 500,000 | 500 |
| `Kimi-K3.1-Pro` | 100 | 100,000 | 100 |
| `gpt-6-astra` | 250 | 250,000 | 250 |
| `claude-opus-5-5` | 40 | 40,000 | 40 |

These are pay-per-token allocations, not provisioned-throughput purchases.
The mocked tests check the five retained capacities and gateway metadata.

Use the catalog SKU's exact `usageName` when checking quota, not an inferred
model-name match. Legacy Fireworks Kimi consumes the shared
`AIServices.GlobalStandard.Fireworks` quota; Kimi K3.1 Pro uses the separate
`AIServices.GlobalStandard.Kimi-K3.1-Pro` quota. Recheck allocations before
recreating or changing deployments; catalog SKU maximums do not override
subscription limits, and another deployment can consume a shared pool.

The 1,000,000-token model context window is not a per-minute allowance.
Long VS Code histories, instructions, tool definitions, and simultaneous
requests can still exceed the rate budget. Honor the backend's retry delay
and reduce or compact oversized chats. Claude Opus 5.5 has a 40,000 TPM
allocation, so large agent requests may still be throttled.
Higher throughput requires the corresponding model quota increase and
another reviewed capacity change.

`model-router`, `gpt-chat-latest`, and `claude-opus-5-5-fast` are no longer
managed or exported by this root. Their gateway aliases and registrations
were removed before their Foundry deployments were deleted.
