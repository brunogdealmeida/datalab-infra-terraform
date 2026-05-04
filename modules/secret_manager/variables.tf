variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "secret_id" {
  description = "Secret Manager secret ID."
  type        = string
}

variable "secret_data" {
  description = "Initial secret value. Leave empty to manage the value via Console or gcloud."
  type        = string
  default     = ""
  sensitive   = true
}

variable "accessors" {
  description = "Service account emails granted secretmanager.secretAccessor on this secret."
  type        = list(string)
  default     = []
}
