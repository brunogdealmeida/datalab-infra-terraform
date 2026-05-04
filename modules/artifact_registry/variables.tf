variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Repository location."
  type        = string
  default     = "us-central1"
}

variable "repository_id" {
  description = "Artifact Registry repository ID."
  type        = string
}

variable "format" {
  description = "Repository format (DOCKER, PYTHON, NPM, etc.)."
  type        = string
  default     = "DOCKER"
}

variable "description" {
  description = "Repository description."
  type        = string
  default     = ""
}
