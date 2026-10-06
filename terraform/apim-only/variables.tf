variable "subscription_id" {
  description = "Azure subscription that receives the isolated APIM AI Gateway deployment."
  type        = string
  default     = "fb7dfa70-78b9-4e56-8d2d-fa2eff765241"
}

variable "tenant_id" {
  description = "Microsoft Entra tenant for the target subscription."
  type        = string
  default     = "16b3c013-d300-468d-ac64-7eda0820b6d3"
}

variable "location" {
  description = "Azure region for the APIM AI Gateway preview architecture."
  type        = string
  default     = "swedencentral"

  validation {
    condition     = lower(var.location) == "swedencentral"
    error_message = "This deployment is intentionally pinned to Sweden Central."
  }
}

variable "resource_group_name" {
  description = "Resource group for the isolated app3, AI Gateway, and Foundry resources."
  type        = string
  default     = "rg-foundry-aigateway-sweden"
}

variable "publisher_name" {
  description = "Publisher name required by the API Management resource."
  type        = string
  default     = "AI Platform Team"
}

variable "publisher_email" {
  description = "Publisher email required by the API Management resource."
  type        = string
  default     = "bulento@microsoft.com"
}

variable "deepseek_monthly_budget_usd" {
  description = "Combined monthly DeepSeek budget allocated across the current AI Gateway runtime keys."
  type        = number
  default     = 200

  validation {
    condition     = var.deepseek_monthly_budget_usd > 0 && var.deepseek_monthly_budget_usd <= 10000000
    error_message = "deepseek_monthly_budget_usd must be greater than 0 and no more than 10,000,000."
  }
}

variable "deepseek_user_count" {
  description = "Number of additional per-user DeepSeek deployments in the existing Foundry account."
  type        = number
  default     = 10

  validation {
    condition     = var.deepseek_user_count >= 0 && var.deepseek_user_count <= 1000 && var.deepseek_user_count == floor(var.deepseek_user_count)
    error_message = "deepseek_user_count must be a whole number between 0 and 1000."
  }
}

variable "deepseek_user_capacity" {
  description = "Data Zone Standard capacity per user deployment; one unit currently grants 1,000 TPM and 1 RPM for this model."
  type        = number
  default     = 25

  validation {
    condition     = var.deepseek_user_capacity >= 1 && var.deepseek_user_capacity == floor(var.deepseek_user_capacity)
    error_message = "deepseek_user_capacity must be a positive whole number within the available regional model quota."
  }
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
  default = {
    architecture = "app3-apim-ai-gateway-foundry"
    environment  = "test"
    managed_by   = "terraform"
  }
}
