locals {
  vpc_name = var.vpc_name != "" ? var.vpc_name : "${var.project_id}-vpc"

  required_apis = toset(concat(
    [
      "run.googleapis.com",
      "artifactregistry.googleapis.com",
      "bigquery.googleapis.com",
      "iam.googleapis.com",
      "secretmanager.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "iamcredentials.googleapis.com",
      "cloudbuild.googleapis.com",
    ],
    var.enable_vpc ? [
      "vpcaccess.googleapis.com",
      "compute.googleapis.com",
    ] : [],
    var.enable_dataform ? [
      "dataform.googleapis.com",
    ] : [],
    anytrue([for job in var.cloud_run_jobs : job.schedule != ""]) ? [
      "cloudscheduler.googleapis.com",
    ] : [],
  ))

  vpc_connector_id = one(module.vpc[*].connector_id)

  # Resolve secret_file → secret_data so file() is called in .tf, not .tfvars.
  # secret_file takes precedence; falls back to secret_data if both are set.
  secrets_resolved = {
    for k, s in var.secrets : k => {
      secret_id   = s.secret_id
      # try() catches file-not-found gracefully: plan succeeds but no secret
      # version is created until the file exists. Once the file is present,
      # re-running apply pushes the version automatically.
      secret_data = s.secret_file != "" ? try(file(s.secret_file), s.secret_data) : s.secret_data
      accessors   = s.accessors
    }
  }
}

resource "google_project_service" "apis" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ─── VPC (optional) ───────────────────────────────────────────────────────────

module "vpc" {
  count  = var.enable_vpc ? 1 : 0
  source = "./modules/vpc"

  project_id         = var.project_id
  region             = var.region
  vpc_name           = local.vpc_name
  subnet_ip_range    = var.subnet_ip_range
  connector_ip_range = var.connector_ip_range

  depends_on = [google_project_service.apis]
}

# ─── Artifact Registry ────────────────────────────────────────────────────────

module "artifact_registry" {
  source = "./modules/artifact_registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = var.repository_id
  format        = var.repository_format
  description   = var.repository_description

  depends_on = [google_project_service.apis]
}

# ─── Docker Builds ────────────────────────────────────────────────────────────

module "docker_build" {
  source   = "./modules/docker_build"
  for_each = var.docker_builds

  project_id        = var.project_id
  context_path      = each.value.context_path
  image_url         = "${module.artifact_registry.repository_url}/${each.key}:${each.value.image_tag}"
  registry_location = var.region

  depends_on = [module.artifact_registry]
}

# ─── IAM / Service Accounts ──────────────────────────────────────────────────

module "iam" {
  source = "./modules/iam"

  project_id       = var.project_id
  service_accounts = var.service_accounts

  depends_on = [google_project_service.apis]
}

# ─── Cloud Run Jobs ──────────────────────────────────────────────────────────

module "cloud_run_jobs" {
  source   = "./modules/cloud_run_job"
  for_each = var.cloud_run_jobs

  project_id      = var.project_id
  region          = var.region
  job_name        = each.key
  image           = each.value.image
  cpu             = each.value.cpu
  memory          = each.value.memory
  timeout_seconds = each.value.timeout_seconds
  max_retries     = each.value.max_retries
  parallelism     = each.value.parallelism
  task_count      = each.value.task_count
  env_vars                        = each.value.env_vars
  runtime_service_account_email   = each.value.service_account
  scheduler_service_account_email = each.value.service_account
  schedule                        = each.value.schedule
  secret_mounts = each.value.secret_mounts
  vpc_connector = local.vpc_connector_id

  depends_on = [
    google_project_service.apis,
    module.iam,
    module.vpc,
    module.docker_build,
  ]
}
# ─── BigQuery ────────────────────────────────────────────────────────────────

module "bigquery" {
  source   = "./modules/bigquery"
  for_each = var.bigquery_datasets

  project_id                 = var.project_id
  dataset_id                 = each.value.dataset_id
  friendly_name              = each.value.friendly_name
  description                = each.value.description
  location                   = each.value.location != "" ? each.value.location : var.region
  delete_contents_on_destroy = each.value.delete_contents_on_destroy
  access                     = each.value.access

  depends_on = [google_project_service.apis, module.iam]
}

# ─── Dataform (optional) ──────────────────────────────────────────────────────

module "dataform" {
  count  = var.enable_dataform ? 1 : 0
  source = "./modules/dataform"

  providers = {
    google      = google
    google-beta = google-beta
  }

  project_id       = var.project_id
  region           = var.region
  repository_name  = var.dataform_repository_name
  git_remote_url   = var.dataform_git_remote_url
  git_token_secret = var.dataform_git_token_secret
  default_branch   = var.dataform_default_branch
  service_account  = var.dataform_service_account

  depends_on = [google_project_service.apis, module.iam]
}

# ─── Workload Identity Federation (optional) ─────────────────────────────────

module "workload_identity_github" {
  count  = var.github_repository != "" ? 1 : 0
  source = "./modules/workload_identity_github"

  project_id                = var.project_id
  github_repository         = var.github_repository
  service_account_email     = var.terraform_service_account
  terraform_service_account = var.terraform_service_account

  depends_on = [google_project_service.apis]
}

# ─── Secret Manager ──────────────────────────────────────────────────────────

module "secrets" {
  source   = "./modules/secret_manager"
  for_each = local.secrets_resolved

  project_id  = var.project_id
  secret_id   = each.value.secret_id
  secret_data = each.value.secret_data
  accessors   = each.value.accessors

  depends_on = [google_project_service.apis]
}
