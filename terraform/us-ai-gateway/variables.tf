variable "foundation_state_path" {
  description = "Path to the local us-foundation state. Null selects the sibling us-foundation/terraform.tfstate."
  type        = string
  default     = null
}

variable "gateway_name" {
  description = "Optional globally unique gateway name. Null uses aigw-us-<foundation suffix>."
  type        = string
  default     = null

  validation {
    condition     = var.gateway_name == null ? true : can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", var.gateway_name))
    error_message = "Use 3-24 lowercase letters, digits, or hyphens, beginning and ending with a letter or digit."
  }
}

variable "runtime_key_name" {
  description = "ARM resource name of the gateway-wide runtime API key; the key value is not read by Terraform."
  type        = string
  default     = "gateway-client"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.runtime_key_name))
    error_message = "Use 3-63 lowercase letters, digits, or hyphens, beginning and ending with a letter or digit."
  }
}

variable "runtime_key_display_name" {
  description = "Nonsecret display label for the gateway-wide runtime API key; the service currently reports All APIs subscription."
  type        = string
  default     = "All APIs subscription"

  validation {
    condition     = length(trimspace(var.runtime_key_display_name)) > 0
    error_message = "The runtime key display name must not be empty."
  }
}

variable "rbac_propagation_delay" {
  description = "Delay before registering the Foundry provider after its role assignment is created."
  type        = string
  default     = "60s"

  validation {
    condition     = length(trimspace(var.rbac_propagation_delay)) > 0
    error_message = "Specify a nonempty duration supported by the time provider, such as 60s."
  }
}

variable "model_endpoint_overrides" {
  description = "Optional native endpoint paths by gateway_foundation.models key, for deployments whose capabilities need an explicit reviewed override."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for paths in values(var.model_endpoint_overrides) :
      length(paths) > 0 &&
      length(distinct(paths)) == length(paths) &&
      alltrue([
        for path in paths : contains([
          "/anthropic/v1/messages",
          "/openai/v1/chat/completions",
          "/openai/v1/responses",
          "/openai/v1/completions",
          "/openai/v1/embeddings",
          "/openai/v1/images/generations",
        ], path)
      ])
    ])
    error_message = "Each override must contain distinct, supported native endpoint paths."
  }
}
