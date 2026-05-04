variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "dataset_id" {
  description = "BigQuery dataset ID."
  type        = string
}

variable "friendly_name" {
  description = "User-friendly dataset name."
  type        = string
  default     = ""
}

variable "description" {
  description = "Dataset description."
  type        = string
  default     = ""
}

variable "location" {
  description = "Dataset location (region or multi-region, e.g. US, EU, us-central1)."
  type        = string
  default     = "US"
}

variable "delete_contents_on_destroy" {
  description = "When true, all tables are deleted when the dataset is destroyed."
  type        = bool
  default     = false
}

variable "access" {
  description = "Dataset access control entries."
  type = list(object({
    role           = string
    user_by_email  = optional(string)
    group_by_email = optional(string)
    special_group  = optional(string)
    iam_member     = optional(string)
  }))
  default = []
}
