# Independent root deployment. Never use the existing demo's Terraform state.
terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"
  features {}
}

variable "subscription_id" {
  description = "Customer subscription ID. Providers must be registered by a subscription administrator."
  type        = string
}

variable "deployment" {
  description = "Deployment settings; the reusable module enforces the schema and validation. See terraform.tfvars.example."
  type        = any
}

variable "provider_secrets" {
  description = "Model-provider environment variables containing secrets. Supply privately; never commit."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "foundry_account_id" {
  description = "Optional ARM resource ID of the Foundry/Cognitive Services account. When set, this root grants LiteLLM's managed identity both OpenAI and model-inference roles on that account."
  type        = string
  default     = null
}

module "litellm" {
  source           = "./modules/litellm"
  settings         = var.deployment
  provider_secrets = var.provider_secrets
}

resource "azurerm_role_assignment" "litellm_foundry_openai_user" {
  count                = var.foundry_account_id == null ? 0 : 1
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.litellm.connection.identity_principal_id
}

resource "azurerm_role_assignment" "litellm_foundry_inference_user" {
  count                = var.foundry_account_id == null ? 0 : 1
  scope                = var.foundry_account_id
  role_definition_name = "Cognitive Services User"
  principal_id         = module.litellm.connection.identity_principal_id
}

output "connection" {
  description = "URLs and identity/network information; not credentials."
  value       = module.litellm.connection
}

output "credentials" {
  description = "Bootstrap credentials. Treat Terraform state and any output containing these as secrets."
  value       = module.litellm.credentials
  sensitive   = true
}

