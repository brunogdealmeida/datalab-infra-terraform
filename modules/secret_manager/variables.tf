variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "secret_id" {
  description = "Secret Manager secret ID."
  type        = string
}

variable "accessors" {
  description = "Service account emails granted secretmanager.secretAccessor on this secret."
  type        = list(string)
  default     = []
}
