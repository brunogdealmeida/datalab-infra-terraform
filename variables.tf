# ─── Project ──────────────────────────────────────────────────────────────────

variable "terraform_service_account" {
  description = "Service account email Terraform will impersonate. Leave empty to use Application Default Credentials directly (not recommended for production)."
  type        = string
  default     = ""
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Default GCP region."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

variable "enable_vpc" {
  description = "Set to true to create a VPC, subnet, and VPC Access Connector."
  type        = bool
  default     = false
}

variable "vpc_name" {
  description = "VPC network name. Defaults to '<project_id>-vpc' when empty."
  type        = string
  default     = ""
}

variable "subnet_ip_range" {
  description = "CIDR for the primary subnet."
  type        = string
  default     = "10.0.0.0/24"
}

variable "connector_ip_range" {
  description = "CIDR for the Serverless VPC Access Connector. Must be a /28."
  type        = string
  default     = "10.8.0.0/28"
}

# ─── Docker Builds ───────────────────────────────────────────────────────────

variable "docker_builds" {
  description = "Map of Docker images to build and push to Artifact Registry. Key is the image name within the repository."
  type = map(object({
    context_path = string
    image_tag    = optional(string, "latest")
  }))
  default = {}
}

# ─── Artifact Registry ────────────────────────────────────────────────────────

variable "repository_id" {
  description = "Artifact Registry repository ID."
  type        = string
}

variable "repository_format" {
  description = "Repository format (DOCKER, PYTHON, NPM, etc.)."
  type        = string
  default     = "DOCKER"
}

variable "repository_description" {
  description = "Repository description."
  type        = string
  default     = ""
}

# ─── IAM / Service Accounts ──────────────────────────────────────────────────

variable "service_accounts" {
  description = "Map of service accounts to create. Key is a logical name."
  type = map(object({
    account_id   = string
    display_name = string
    roles        = list(string)
  }))
  default = {}
}

# ─── Cloud Run Jobs ──────────────────────────────────────────────────────────

variable "cloud_run_jobs" {
  description = "Map of Cloud Run Jobs to create. Key is used as the job name."
  type = map(object({
    image           = string
    cpu             = optional(string, "1")
    memory          = optional(string, "512Mi")
    timeout_seconds = optional(number, 3600)
    max_retries     = optional(number, 0)
    parallelism     = optional(number, 1)
    task_count      = optional(number, 1)
    env_vars        = optional(map(string), {})
    service_account = optional(string, "")
    schedule        = optional(string, "")
    secret_mounts = optional(list(object({
      volume_name = string
      secret_id   = string
      version     = optional(string, "latest")
      mount_path  = string
      file_name   = string
    })), [])
  }))
  default = {}
}

# ─── BigQuery ────────────────────────────────────────────────────────────────

variable "bigquery_datasets" {
  description = "Map of BigQuery datasets to create. Key is a logical name."
  type = map(object({
    dataset_id                 = string
    friendly_name              = optional(string, "")
    description                = optional(string, "")
    location                   = optional(string, "")
    delete_contents_on_destroy = optional(bool, false)
    access = optional(list(object({
      role           = string
      user_by_email  = optional(string)
      group_by_email = optional(string)
      special_group  = optional(string)
      iam_member     = optional(string)
    })), [])
  }))
  default = {}
}

# ─── Dataform ────────────────────────────────────────────────────────────────

variable "enable_dataform" {
  description = "Set to true to create a Dataform repository."
  type        = bool
  default     = false
}

variable "dataform_repository_name" {
  description = "Dataform repository name."
  type        = string
  default     = ""
}

variable "dataform_git_remote_url" {
  description = "Git remote URL for Dataform (e.g. https://github.com/org/repo.git)."
  type        = string
  default     = ""
}

variable "dataform_git_token_secret" {
  description = "Secret Manager secret ID holding the Git authentication token."
  type        = string
  default     = ""
}

variable "dataform_default_branch" {
  description = "Default Git branch for Dataform."
  type        = string
  default     = "main"
}

variable "dataform_service_account" {
  description = "Service account email for Dataform workflow execution."
  type        = string
  default     = ""
}

# ─── Workload Identity Federation ────────────────────────────────────────────

variable "github_repository" {
  description = "GitHub repository in 'org/repo' format. When set, a Workload Identity pool and provider are created so GitHub Actions can authenticate without SA keys."
  type        = string
  default     = ""
}

# ─── Secret Manager ──────────────────────────────────────────────────────────

variable "secrets" {
  description = "Map of secrets to create in Secret Manager. Key is a logical name."
  type = map(object({
    secret_id   = string
    secret_data = optional(string, "")  # inline value; use -var in CI pipelines
    secret_file = optional(string, "")  # path to a local file; evaluated at plan time
    accessors   = optional(list(string), [])
  }))
  default = {}
}
