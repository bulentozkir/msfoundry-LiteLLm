variable "subscription_id" {
  description = "Subscription containing the existing US resource group."
  type        = string
  default     = "fb7dfa70-78b9-4e56-8d2d-fa2eff765241"
}

variable "tenant_id" {
  description = "Microsoft Entra tenant for the target subscription."
  type        = string
  default     = "16b3c013-d300-468d-ac64-7eda0820b6d3"
}

variable "resource_group_name" {
  description = "Existing East US 2 resource group. This root does not manage or delete the group."
  type        = string
  default     = "rg-foundry-aigateway"
}

variable "claude_provider_data" {
  description = "Actual Anthropic Marketplace attestation. Applying Claude deployments accepts the partner offer terms on behalf of this organization."
  type = object({
    organizationName = string
    countryCode      = string
    industry         = string
  })
  nullable = false

  validation {
    condition = (
      can(regex("\\S", var.claude_provider_data.organizationName)) &&
      can(regex("^[A-Z]{2}$", var.claude_provider_data.countryCode)) &&
      contains(["technology", "finance", "healthcare", "education", "retail", "manufacturing", "government", "media", "other"], var.claude_provider_data.industry)
    )
    error_message = "Supply the real legal entity, an uppercase two-letter country code, and a supported lowercase industry."
  }
}

variable "enable_deepseek" {
  description = "Deploy DeepSeek once its existing 250 units of GlobalStandard quota are released."
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Name of the project recreated from the former Foundry account."
  type        = string
  default     = "ai-project-8f17c2a9"
}
