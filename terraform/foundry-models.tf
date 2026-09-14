# Model deployments are outside the reusable MLflow gateway platform. The existing
# Foundry account and GPT deployments remain managed as before.
variable "phi_model_alias" {
  description = "Separate MLflow gateway model alias used by /chatphi and usage reporting."
  type        = string
  default     = "phi-4"
}

resource "azurerm_cognitive_deployment" "phi" {
  name                   = "Phi-4"
  cognitive_account_id   = var.foundry_account_id
  version_upgrade_option = "NoAutoUpgrade"

  model {
    format  = "Microsoft"
    name    = "Phi-4"
    version = "7"
  }

  sku {
    name     = "GlobalStandard"
    capacity = 10
  }
}

# Phi uses the Foundry Model Inference data plane, rather than the OpenAI-only
# role already assigned for Mini. Scope this permission to the same account.
resource "azurerm_role_assignment" "mlflow_foundry_inference_user" {
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.mlflow.principal_id
}

moved {
  from = azurerm_role_assignment.litellm_foundry_inference_user
  to   = azurerm_role_assignment.mlflow_foundry_inference_user
}

locals {
  foundry_model_inference_endpoint = "https://${reverse(split("/", var.foundry_account_id))[0]}.services.ai.azure.com/models"
}

output "phi_deployment_name" {
  description = "Phi deployment in the existing Foundry account."
  value       = azurerm_cognitive_deployment.phi.name
}