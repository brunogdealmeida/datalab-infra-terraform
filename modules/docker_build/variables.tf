variable "project_id" {
  description = "GCP project ID where Cloud Build will run."
  type        = string
}

variable "context_path" {
  description = "Path to the Docker build context (directory containing the Dockerfile)."
  type        = string
}

variable "image_url" {
  description = "Full image URL including tag (e.g. us-central1-docker.pkg.dev/project/repo/image:tag)."
  type        = string
}

variable "registry_location" {
  description = "Artifact Registry location (e.g. us-central1)."
  type        = string
}
