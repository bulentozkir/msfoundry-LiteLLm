variable "subscription_id" {
  description = "Azure subscription ID to deploy into. Leave null to use the az CLI/azd active subscription."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for all resources (Container Apps, storage, Key Vault)."
  type        = string
  default     = "northcentralus"
}

variable "resource_group_name" {
  description = "Name of the resource group to create for the LiteLLM test deployment."
  type        = string
  default     = "rg-litellm-foundry-test"
}

variable "project_name" {
  description = "Short name used to build resource names (storage account, Key Vault). Keep lowercase alphanumeric, max ~10 chars, since it feeds into name-length-limited resources."
  type        = string
  default     = "litellm"

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.project_name))
    error_message = "project_name must be 1-10 lowercase alphanumeric characters (no hyphens/spaces) to fit storage account and Key Vault name limits."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    project     = "msfoundry-litellm"
    environment = "test"
    managed_by  = "terraform"
  }
}

# ---- MLflow gateway container ----

variable "mlflow_container_cpu" {
  description = "vCPU allocated to the mlflow container (must pair with a valid Container Apps Consumption cpu/memory combo)."
  type        = number
  default     = 1.5
}

variable "mlflow_min_replicas" {
  description = "Minimum mlflow container replicas (keeps at least this many warm)."
  type        = number
  default     = 1
}

variable "mlflow_max_replicas" {
  description = "Maximum mlflow container replicas to autoscale out to."
  type        = number
  default     = 5
}

variable "mlflow_scale_concurrent_requests" {
  description = "Concurrent HTTP requests per replica before Container Apps scales out another replica."
  type        = number
  default     = 50
}

variable "mlflow_container_memory" {
  description = "Memory allocated to the mlflow container (must pair with mlflow_container_cpu per Container Apps Consumption allocation rules). 3Gi gives headroom for mlflow's --workers 2 processes, each loading the full mlflow[genai] dependency set."
  type        = string
  default     = "3Gi"
}

variable "mlflow_model_alias" {
  description = "The model name clients call through the MLflow gateway (e.g. 'gpt-5-mini'). Can be any friendly alias."
  type        = string
  default     = "gpt-5-mini"
}

# ---- MLflow gateway basic auth (mlflow.server.auth, HTTP Basic) ----

variable "mlflow_admin_username" {
  description = "Admin username for the MLflow gateway's basic-auth login (protects the gateway UI/API - see mlflow-gateway-app.tf)."
  type        = string
  default     = "aiadmin"
}

variable "mlflow_admin_password" {
  description = "Admin password for the MLflow gateway's basic-auth login. Set via terraform.tfvars, not committed."
  type        = string
  sensitive   = true
}

# ---- Chat client 2 (access-key only, no Entra ID) ----

variable "chat_client2_app_name" {
  description = "Globally-unique Azure App Service name for the second (access-key only) chat client."
  type        = string
  default     = "litellm-chat2-ntzf8l"
}

# ---- Microsoft Foundry / Azure OpenAI backend ----

variable "azure_openai_endpoint" {
  description = "Foundry/Azure OpenAI-compatible endpoint (api_base), e.g. 'https://<account>.services.ai.azure.com' or 'https://<account>.openai.azure.com'."
  type        = string
}

variable "azure_openai_api_version" {
  description = "Azure OpenAI API version used by the MLflow gateway's azuread provider."
  type        = string
  default     = "2024-10-21"
}

variable "azure_openai_deployment_name" {
  description = "The model deployment name in the Foundry project that the MLflow gateway will proxy to (e.g. 'gpt-5-mini')."
  type        = string
}

variable "foundry_account_id" {
  description = "Full ARM resource ID of the Foundry/Cognitive Services (AIServices) account backing azure_openai_deployment_name. Used to grant the Container App's identity 'Cognitive Services OpenAI User' so the gateway authenticates via Managed Identity (no API key - required since this account has disableLocalAuth enforced by policy)."
  type        = string
}
