terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.8"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.8"
    }
  }
}

locals {
  dataform_roles = var.service_account != "" ? [
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/secretmanager.secretAccessor",
  ] : []
}

resource "google_dataform_repository" "repo" {
  provider = google-beta

  project = var.project_id
  region  = var.region
  name    = var.repository_name

  dynamic "git_remote_settings" {
    for_each = var.git_remote_url != "" ? [1] : []
    content {
      url            = var.git_remote_url
      default_branch = var.default_branch
      authentication_token_secret_version = var.git_token_secret != "" ? (
        "projects/${var.project_id}/secrets/${var.git_token_secret}/versions/latest"
      ) : null
    }
  }
}

resource "google_project_iam_member" "dataform_sa_roles" {
  for_each = toset(local.dataform_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${var.service_account}"
}
