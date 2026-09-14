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
      version = "~> 3.6"
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

module "mlflow" {
  source           = "./modules/mlflow"
  settings         = var.deployment
  provider_secrets = var.provider_secrets
}

output "connection" {
  description = "URLs and identity/network information; not credentials."
  value       = module.mlflow.connection
}

output "credentials" {
  description = "Bootstrap credentials. Treat Terraform state and any output containing these as secrets."
  value       = module.mlflow.credentials
  sensitive   = true
}

