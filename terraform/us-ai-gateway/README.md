# East US 2 dedicated AI Gateway

This root consumes the **local** `gateway_foundation` output from the sibling
`us-foundation` Terraform state. It manages a new
`Microsoft.ApiManagement/aigateways` resource, not the retired API Management
`service`/`AIGateway` tier. It does not own the foundation, its state, or the
resource group.

The gateway has a public HTTPS frontend and a system-assigned identity. Its
backend uses the foundation's `Microsoft.App/environments`-delegated subnet to
reach the private Foundry account; local Foundry authentication and public
Foundry networking must remain disabled. The identity receives **Foundry User**
(`53ca6127-db72-4b80-b1b0-d745d6d5456d`) at the Foundry account scope.
The configuration creates a Foundry provider, registers every supported
deployment in the foundation output, preserves each deployment name as its
callable alias, and creates a gateway-wide runtime API key resource. Terraform
does **not** call `listSecrets`, expose the key, or deliberately store its value.
The key resource is named `gateway-client`; the service currently reports its
display label as `All APIs subscription`.

The preview service's backend subnet cannot be changed in place. A subnet
change triggers gateway replacement, and `prevent_destroy` blocks it, including
an ordinary `terraform destroy`. Plan and approve a separate migration before
deliberately changing that protection. The public gateway frontend cannot use
the old gateway's inbound private endpoint. Restrict caller access appropriately;
runtime keys authorize the whole gateway, not an individual model.

## Contract and limitations

The live gateway portal uses `2025-09-01-preview` for this resource type and its
children. Its create request supplies the backend subnet, public frontend and
identity, but does **not** set a SKU: this root likewise leaves the SKU to the
service and checks that the returned SKU is `Premium`. It uses the live
`properties.displayName` fields for providers, models and keys. These preview
details differ from the separately published `2026-09-01-preview` gateway
template and `2026-11-01` child-resource examples; verify the live API contract
and price again before any deployment. The plan cannot prove the selected SKU:
the postcondition runs after creation, so a failed SKU check can leave a
provisioned, billable gateway that requires an explicitly approved cleanup.

The portal's source uses Foundry deployment capability flags to select native
endpoint paths and falls back to chat completions if no flag is true.
Anthropic models use native Messages. If a deployment advertises only
unrecognized capabilities, planning fails instead of inventing a route; use a
reviewed `model_endpoint_overrides` entry when appropriate. The root also
rejects colliding normalized resource names and the explicitly excluded Fable,
Phi, GPT mini and GLM models.

The live gateway registers `model-router`, `gpt-6-astra`, `FW-Kimi-K3`,
`FW-DeepSeek-V4.1-Flash`, `gpt-chat-latest`, `claude-opus-5-5`, and
`claude-opus-5-5-fast`. Direct inference succeeded for all seven.
`gpt-chat-latest` version `2026-10-07` is the Preview, Standard-quota
replacement for the provisioned-only Qwen candidate. Its discovered Chat
Completions and Responses endpoints both returned nonempty replies, and an
existing Kimi alias was also retested successfully. The existing gateway,
runtime key, identity, network, and other registrations were not changed.

This root does not deploy models. After a new model is actually deployed by
the foundation and appears in its output, this root plans its registration
and alias on the next apply. Review its discovered endpoint capabilities and
any required override. Removing a deployment from that output plans the
removal of its gateway registration and alias.

Mock tests verify request construction, not a live deployment or successful
inference. The gateway's backend subnet and Foundry private endpoint must
share effective routing and private DNS; verify those prerequisites and
Foundry endpoint resolution when changing the network. A fixed RBAC delay is
not proof of propagation. The frontend hostname is read from
`properties.frontend.defaultHostname`, never guessed.

Relevant Microsoft sources:

- [Migration and networking limitations](https://learn.microsoft.com/azure/ai-gateway/ai-gateway-resource)
- [Gateway quickstart, identity, aliases and runtime keys](https://learn.microsoft.com/azure/ai-gateway/quickstart-create-ai-gateway)
- [Published dedicated gateway ARM template](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/aigateways)
- [Official portal request implementation](https://ai.gateway.azure.com/assets/index-Dd_m5Qbu.js)
- [Official REST specification and child-resource examples](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/apimanagement/resource-manager/Microsoft.ApiManagement/AIGateway)

## Review and maintenance

No Azure resources are changed by the mock-provider tests. After the foundation
has been separately reviewed and successfully applied, its state must contain
the intended models and the nonsecret `gateway_foundation` output. Access to
that local state must be restricted: Terraform remote-state readers can access
the complete state snapshot, which may contain Foundry attestation information.
Never print or commit it. The optional `foundation_state_path` variable may
select another local copy of that same foundation state.

From the repository root in PowerShell:

```powershell
terraform -chdir=terraform\us-ai-gateway init
terraform -chdir=terraform\us-ai-gateway fmt -check
terraform -chdir=terraform\us-ai-gateway validate
terraform -chdir=terraform\us-ai-gateway test
terraform -chdir=terraform\us-ai-gateway plan -out=reviewed.tfplan
```

Only after explicit authorization and review of the plan, SKU, cost, subnet,
private DNS, model list and RBAC, an operator may apply the saved plan:

```powershell
terraform -chdir=terraform\us-ai-gateway apply reviewed.tfplan
```

After provisioning, an authorized operator can use the AI Gateway portal's
**Access > Keys** workflow to retrieve the created key into an approved secret
store without printing it or adding it to Terraform state. Use
`Authorization: Bearer <key>` for requests. Check every alias and its actual
native endpoint, private DNS resolution, and successful inference before any
client or VS Code cutover. `gateway_url` and `model_endpoint_urls` are based on
the hostname returned by Azure; do not infer a hostname from the gateway name.
If the generated gateway name is unavailable, supply another valid
`gateway_name` before reviewing a new plan.
