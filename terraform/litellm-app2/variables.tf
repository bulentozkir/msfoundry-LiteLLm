variable "subscription_id" {
  type    = string
  default = "fb7dfa70-78b9-4e56-8d2d-fa2eff765241"
}

variable "tenant_id" {
  type    = string
  default = "16b3c013-d300-468d-ac64-7eda0820b6d3"
}

variable "resource_group_name" {
  type    = string
  default = "rg-foundry-aigateway-sweden"
}

variable "foundry_account_name" {
  type    = string
  default = "fdry-aigw-8ps1sz"
}

variable "app_service_plan_name" {
  description = "Existing Linux App Service plan, read without modifying its SKU."
  type        = string
  default     = "asp-chat3-8ps1sz"
}

variable "name_suffix" {
  type    = string
  default = "8ps1sz"
}

variable "litellm_image" {
  description = "Official LiteLLM v1.101.0 image pinned by immutable digest."
  type        = string
  default     = "ghcr.io/berriai/litellm@sha256:d295634e09c648dcdb72c4cc2dd226f5fb87823a73e88cbbed6f205e4deb044b"
}

variable "postgres_sku" {
  description = "PostgreSQL Flexible Server size; B1ms is the smallest Burstable option."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "redis_sku" {
  description = "Azure Managed Redis size; Balanced B0 provides 0.5 GB for this non-HA test deployment."
  type        = string
  default     = "Balanced_B0"
}

variable "postgres_allowed_ip_addresses" {
  description = "Explicit IPv4 egress allowlist for the existing LiteLLM Container App. Refresh before deployment; no allow-all-Azure rule is created."
  type        = set(string)

  validation {
    condition = length(var.postgres_allowed_ip_addresses) > 0 && alltrue([
      for address in var.postgres_allowed_ip_addresses :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", address)) && can(cidrhost("${address}/32", 0)) && address != "0.0.0.0"
    ])
    error_message = "Supply the Container App's explicit outbound IPv4 addresses; empty and allow-all-Azure lists are not allowed."
  }
}

variable "tags" {
  type = map(string)
  default = {
    architecture = "chat2-litellm-foundry"
    environment  = "test"
    managed_by   = "terraform"
  }
}