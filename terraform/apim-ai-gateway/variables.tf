variable "foundation_state_path" {
  description = "Local state of the apim-only foundation root. Null uses the sibling apim-only/terraform.tfstate. Never point both roots at the same writable state."
  type        = string
  default     = null
}

variable "ai_gateway_enabled" {
  description = "Enable the AI Gateway preview instance and its children. Disable and apply before enabling Standard v2 on the shared outbound subnet."
  type        = bool
  default     = true
}

variable "gateway_name" {
  description = "Optional globally unique gateway name, for example when a previous name is reserved by Azure soft-delete."
  type        = string
  default     = null

  validation {
    condition     = var.gateway_name == null || can(regex("^[a-zA-Z]([a-zA-Z0-9-]{0,48}[a-zA-Z0-9])?$", var.gateway_name))
    error_message = "Use a 1-50 character APIM name starting with a letter and ending with a letter or digit."
  }
}
