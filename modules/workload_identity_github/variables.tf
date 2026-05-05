variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in 'org/repo' format, for example 'myorg/myrepo'."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use the 'owner/repository' format."
  }
}

variable "service_account_email" {
  description = "Email of the service account GitHub Actions will impersonate."
  type        = string
}

variable "terraform_service_account" {
  description = "Email of the Terraform service account. When set, Terraform grants it roles/iam.workloadIdentityPoolAdmin."
  type        = string
  default     = ""
}

variable "pool_id" {
  description = "Workload Identity Pool ID."
  type        = string
  default     = "github-pool"
}

variable "pool_display_name" {
  description = "Display name for the Workload Identity Pool."
  type        = string
  default     = "GitHub Actions Pool"
}

variable "provider_id" {
  description = "Workload Identity Pool Provider ID."
  type        = string
  default     = "github-provider"
}

variable "provider_display_name" {
  description = "Display name for the Workload Identity Pool Provider."
  type        = string
  default     = "GitHub Provider"
}
