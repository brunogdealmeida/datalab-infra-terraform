variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Dataform repository region."
  type        = string
}

variable "repository_name" {
  description = "Dataform repository name."
  type        = string
}

variable "git_remote_url" {
  description = "Git remote URL (e.g. https://github.com/org/repo.git). Leave empty to configure manually."
  type        = string
  default     = ""
}

variable "default_branch" {
  description = "Default Git branch."
  type        = string
  default     = "main"
}

variable "git_token_secret" {
  description = "Secret Manager secret ID holding the Git token. Leave empty to configure manually."
  type        = string
  default     = ""
}

variable "service_account" {
  description = "Service account email for Dataform workflow execution. Leave empty to skip IAM grants."
  type        = string
  default     = ""
}
