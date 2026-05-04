data "google_project" "project" {
  project_id = var.project_id
}

# Grant the Terraform SA permission to manage WIF pools.
# sa-terraform already has projectIamAdmin, so it can grant this role to itself.
# The pool creation depends_on this binding to ensure ordering.
resource "google_project_iam_member" "terraform_sa_wif_admin" {
  count   = var.terraform_service_account != "" ? 1 : 0
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${var.terraform_service_account}"
}

# GCP IAM changes are eventually consistent — wait for the binding to propagate
# before attempting to create the pool, otherwise the apply fails with 403.
resource "time_sleep" "iam_propagation" {
  count           = var.terraform_service_account != "" ? 1 : 0
  create_duration = "60s"
  depends_on      = [google_project_iam_member.terraform_sa_wif_admin]
}

resource "google_iam_workload_identity_pool" "pool" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = var.pool_display_name
  description               = "Workload Identity Pool for GitHub Actions CI/CD"

  depends_on = [time_sleep.iam_propagation]
}

resource "google_iam_workload_identity_pool_provider" "provider" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = var.provider_display_name

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "attribute.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/${var.github_repository}"
}
