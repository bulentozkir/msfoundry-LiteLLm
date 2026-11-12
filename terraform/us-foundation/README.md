# East US 2 Foundry foundation

This root manages the private Foundry account and project, model deployments,
VNet, subnets, network security groups, private endpoint, and private DNS.
The existing `rg-foundry-aigateway` resource group is read, not managed by
Terraform. The dedicated gateway is owned by the independent
[US AI Gateway root](../us-ai-gateway/README.md).

Foundry public networking and local authentication are disabled. The gateway
uses its managed identity to connect through the private endpoint. The active
foundation deploys DeepSeek, Kimi K3, model-router, GPT-6 Astra,
`gpt-chat-latest`, Claude Opus 5.5, and Claude Opus 5.5 Fast; DeepSeek's
default capacity is 250. Applying the Claude deployments accepts the
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
.\terraform\us-foundation\tests\verify-router-actions.ps1
terraform -chdir=terraform\us-foundation plan -out=reviewed.tfplan
```

The PowerShell check runs the mocked tests and inspects only the router plan
actions, without printing their test state.

Review the plan, quota, cost, and networking before applying it. After adding,
removing, or changing the identity of a foundation deployment, review and
apply the separate gateway plan to update model registrations. Capacity-only
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

The following `GlobalStandard` allocations use the full approved East US 2
quota for each deployed model, verified on November 12, 2026:

| Deployment | Capacity units | Tokens/minute | Requests/minute |
|---|---:|---:|---:|
| `FW-DeepSeek-V4.1-Flash` | 250 | 250,000 | 250 |
| `FW-Kimi-K3` | 500 | 500,000 | 500 |
| `model-router` | 1,000 | 1,000,000 | 1,000 |
| `gpt-6-astra` | 250 | 250,000 | 250 |
| `gpt-chat-latest` | 1,000 | 1,000,000 | 1,000 |
| `claude-opus-5-5` | 40 | 40,000 | 40 |
| `claude-opus-5-5-fast` | 16 | 16,000 | 16 |

Kimi and DeepSeek were already at their approved maximums. The other five
deployments increased in place, retaining model versions, routing, gateway
aliases, credentials, and private networking. This is pay-per-token
capacity, not a provisioned-throughput purchase. The mocked tests assert all
seven capacities and their gateway metadata.

Use the catalog SKU's exact `usageName` when checking quota, not an inferred
model-name match. The router uses `OpenAI.GlobalStandard.ModelRouter`, not
its separate fine-tuning pool. Kimi consumes the entire shared
`AIServices.GlobalStandard.Fireworks` quota. Recheck allocations before
recreating or changing deployments; catalog SKU maximums do not override
subscription limits, and another deployment can consume a shared pool.

The 1,000,000-token model context window is not a per-minute allowance.
Long VS Code histories, instructions, tool definitions, and simultaneous
requests can still exceed the rate budget. Honor the backend's retry delay
and reduce or compact oversized chats. Claude's approved quotas remain
40,000 and 16,000 TPM, so large agent requests may still be throttled.
Higher throughput requires the corresponding model quota increase and
another reviewed capacity change.

## Model-router policy and capacity

The router uses balanced routing over an explicit subset: OpenAI
`gpt-6-astra` version `2026-09-03`, `gpt-5.6-sol` and `gpt-5.6-terra` version
`2026-07-09`, and Fireworks `FW-Kimi-K3` version `1`. GLM is not in this
list. Override `model_router_routing_models` to change the complete subset;
provide at least two distinct model name/version pairs so a fallback remains
available. New catalog models are not added automatically. Confirm that any
replacement model and version are supported by the router and have the
context capacity required by clients.

The deployed `GlobalStandard` capacity is **1,000 units**, with
1,000,000 tokens and 1,000 requests per minute, increased from 100 units.
All 1,000 units of the router's approved regional quota are allocated.
Tokens per minute is a shared rate budget, not a guarantee that a
1,000,000-token input will fit: output reservations, request overhead, other
traffic, request limits, and smaller model context windows can consume or
constrain the budget. The router and the current subset were reported to have
1,048,576-token context windows; changing client context settings is separate
from this foundation.

AzureRM 5.6.0 does not expose routing. The router therefore has a single
`azapi_resource.model_router` owner using API `2025-10-01-preview`; it sends
the entire desired routing list rather than an AzAPI partial-update overlay,
which can retain omitted named list entries. A read-only lookup supplies
existing tags and the other writable deployment fields supported by this API
to the full update, while the declared model, SKU, and routing remain
authoritative. The lookup tolerates a missing router so recreation can use
Azure defaults. Re-plan immediately before applying to avoid overwriting
out-of-band changes made after the lookup.

The `moved` block supports transferring the legacy
`azurerm_cognitive_deployment.model["model_router"]` binding to
`azapi_resource.model_router`; do not separately import it or run
`terraform state mv`. The active state binding has already been migrated
through a refresh-only apply. The subsequent capacity increase to 1,000
preserves the existing balanced four-model subset. Review future changes
with a refreshed, access-controlled plan: capacity changes should be in
place, not create, delete, or replace the deployment. Stop if other
deployment properties would change unexpectedly, and verify the preview API
and available quota before applying.

## Standard-quota replacement

`gpt-chat-latest` version `2026-10-07` (Preview) replaces the previously staged
Qwen candidate. It is deployed with `GlobalStandard` capacity 1,000 and
`NoAutoUpgrade`, using the subscription's existing quota rather than
provisioned capacity. At verification on November 12, 2026, its East US 2
quota usage was 1,000 of 1,000 units. The deployment reports 1,000,000 tokens
and 1,000 requests per minute; these rate limits are separate from its context
window. Inference is billed by token usage, without a provisioned-capacity
commitment.

No Qwen deployment or provisioned-capacity opt-in remains in this root. The
new deployment is included in `gateway_foundation`, and the gateway registers
the exact `gpt-chat-latest` alias with Chat Completions and Responses
endpoints. Both endpoints returned nonempty replies in live gateway tests,
and an existing Kimi alias still succeeded. Review future model versions and
quota changes explicitly. The global SKU does not guarantee US-only
inference processing.
