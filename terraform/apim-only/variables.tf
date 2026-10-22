variable "subscription_id" {
  description = "Azure subscription for the shared Foundry foundation and optional Standard v2 gateway."
  type        = string
  default     = "fb7dfa70-78b9-4e56-8d2d-fa2eff765241"
}

variable "tenant_id" {
  description = "Microsoft Entra tenant for the target subscription."
  type        = string
  default     = "16b3c013-d300-468d-ac64-7eda0820b6d3"
}

variable "location" {
  description = "Azure region for the shared Foundry and gateway architecture."
  type        = string
  default     = "swedencentral"

  validation {
    condition     = lower(var.location) == "swedencentral"
    error_message = "This deployment is intentionally pinned to Sweden Central."
  }
}

variable "resource_group_name" {
  description = "Resource group for the shared Foundry foundation and selected gateway tier."
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

variable "standard_gateway_enabled" {
  description = "Enable the Standard v2 gateway and its children. Disable before enabling the separate AI Gateway root; Foundry, shared networking, and Entra registrations are retained."
  type        = bool
  default     = true
}

variable "gateway_name" {
  description = "Optional Standard v2 gateway name when recreating a deleted service. Entra registration identifiers remain stable."
  type        = string
  default     = null

  validation {
    condition     = var.gateway_name == null || can(regex("^[a-zA-Z]([a-zA-Z0-9-]{0,48}[a-zA-Z0-9])?$", var.gateway_name))
    error_message = "Use a 1-50 character APIM name starting with a letter and ending with a letter or digit."
  }
}

variable "entra_model_principal_ids" {
  description = "Explicit per-model Entra role assignments to user, group, or service-principal object IDs. Omitted models grant no access."
  type        = map(set(string))
  default     = {}

  validation {
    condition = alltrue([
      for model_id, principal_ids in var.entra_model_principal_ids :
      contains(["gpt5_4_mini", "phi", "deepseek"], model_id) &&
      alltrue([for id in principal_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    ])
    error_message = "Use only gpt5_4_mini, phi, or deepseek with valid Entra principal object UUIDs."
  }
}

variable "claude_provider_data" {
  description = "Actual Anthropic Marketplace attestation. Applying the Claude deployment accepts its partner offer terms on behalf of this organization."
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
    error_message = "Supply the real legal entity, an uppercase two-letter country code, and a supported lowercase industry; software maps to technology."
  }
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
  default = {
    architecture = "apim-ai-gateway-foundry"
    environment  = "test"
    managed_by   = "terraform"
  }
}
