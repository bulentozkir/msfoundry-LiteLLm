# ---------------------------------------------------------------------------
# Chat3 + APIM (Developer) variables.
# ---------------------------------------------------------------------------

variable "chat_client3_app_name" {
  description = "Globally-unique Azure App Service name for chat3 (APIM-backed web app)."
  type        = string
  default     = "litellm-chat3-ntzf8l"
}

variable "apim_publisher_name" {
  description = "Publisher display name for APIM Developer instance metadata."
  type        = string
  default     = "Platform Team"
}

variable "apim_publisher_email" {
  description = "Publisher email for APIM Developer instance metadata."
  type        = string
  default     = "platform-team@example.com"
}

variable "apim_phi_api_version" {
  description = "API version used for Foundry model-inference calls in the APIM phi branch."
  type        = string
  default     = "2024-05-01-preview"
}
