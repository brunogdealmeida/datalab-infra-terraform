variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "runtime_service_account_email" {
  description = "Service account email to run the Cloud Run Job. Leave empty to use the default Compute Engine service account."
  type        = string
  default     = ""
}

variable "time_zone" {
  description = "Time zone for the Cloud Scheduler."
  type        = string
  default     = "UTC"
}

variable "scheduler_service_account_email" {
  description = "Service account email for Cloud Scheduler to impersonate when triggering the job. Leave empty to use the default Compute Engine service account."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the Cloud Run Job."
  type        = bool
  default     = false
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "job_name" {
  description = "Cloud Run Job name."
  type        = string
}

variable "image" {
  description = "Container image URL."
  type        = string
}

variable "cpu" {
  description = "vCPU allocation (e.g. '1', '2')."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation (e.g. '512Mi', '1Gi')."
  type        = string
  default     = "512Mi"
}

variable "timeout_seconds" {
  description = "Maximum task duration in seconds."
  type        = number
  default     = 3600
}

variable "max_retries" {
  description = "Maximum number of retries per task."
  type        = number
  default     = 0
}

variable "parallelism" {
  description = "Maximum number of tasks that may run concurrently."
  type        = number
  default     = 1
}

variable "task_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "env_vars" {
  description = "Environment variables to inject into the container."
  type        = map(string)
  default     = {}
}

variable "schedule" {
  description = "Cron expression for Cloud Scheduler. Empty string disables scheduling."
  type        = string
  default     = ""
}

variable "vpc_connector" {
  description = "VPC Access Connector ID to attach to the job. Empty string disables VPC."
  type        = string
  default     = ""
}

variable "secret_mounts" {
  description = "Secret Manager secrets to mount as files inside the container."
  type = list(object({
    volume_name = string
    secret_id   = string
    version     = optional(string, "latest")
    mount_path  = string
    file_name   = string
  }))
  default = []
}
