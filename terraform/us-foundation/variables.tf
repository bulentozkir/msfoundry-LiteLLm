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

variable "model_router_routing_models" {
  description = "Explicit model-router subset; changing it replaces the complete routing list."
  type = list(object({
    format  = string
    name    = string
    version = string
  }))
  default = [
    { format = "OpenAI", name = "gpt-6-astra", version = "2026-09-03" },
    { format = "OpenAI", name = "gpt-5.6-sol", version = "2026-07-09" },
    { format = "OpenAI", name = "gpt-5.6-terra", version = "2026-07-09" },
    { format = "Fireworks", name = "FW-Kimi-K3", version = "1" },
  ]
  nullable = false

  validation {
    condition = try(
      length(var.model_router_routing_models) >= 2 &&
      alltrue([
        for model in var.model_router_routing_models :
        trimspace(model.format) != "" && trimspace(model.format) == model.format &&
        trimspace(model.name) != "" && trimspace(model.name) == model.name &&
        trimspace(model.version) != "" && trimspace(model.version) == model.version
      ]) &&
      length(distinct([
        for model in var.model_router_routing_models :
        jsonencode([lower(model.name), model.version])
      ])) == length(var.model_router_routing_models),
      false
    )
    error_message = "Supply at least two distinct model name/version pairs with nonempty, whitespace-free format, name, and version values."
  }
}

variable "project_name" {
  description = "Name of the project recreated from the former Foundry account."
  type        = string
  default     = "ai-project-8f17c2a9"
}
