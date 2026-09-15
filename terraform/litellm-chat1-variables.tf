# ---------------------------------------------------------------------------
# Chat1 (LiteLLM-backed) input variables.
# ---------------------------------------------------------------------------

variable "chat_client1_app_name" {
  description = "Globally-unique Azure App Service name for chat1 (LiteLLM-backed web app)."
  type        = string
  default     = "litellm-chat1-ntzf8l"
}

variable "litellm_chat1_base_url" {
  description = "Base URL for chat1 to call LiteLLM's OpenAI-compatible endpoint, typically https://<host>/v1."
  type        = string
  default     = "https://replace-with-litellm.example.com/v1"

  validation {
    condition     = can(regex("^https://", var.litellm_chat1_base_url))
    error_message = "litellm_chat1_base_url must start with https://"
  }
}

variable "litellm_chat1_api_key" {
  description = "Optional LiteLLM API key for chat1 bearer auth (for example a scoped virtual key)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "litellm_chat1_model_alias" {
  description = "Model alias chat1 sends for the Mini path through LiteLLM."
  type        = string
  default     = "gpt-5.4-mini"
}

variable "litellm_chat1_phi_model_alias" {
  description = "Model alias chat1 sends for the Phi path through LiteLLM."
  type        = string
  default     = "phi-4"
}
