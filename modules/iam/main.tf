locals {
  sa_role_bindings = merge([
    for sa_key, sa in var.service_accounts : {
      for role in sa.roles :
      "${sa_key}--${role}" => {
        sa_key = sa_key
        role   = role
      }
    }
  ]...)
}

resource "google_service_account" "sa" {
  for_each = var.service_accounts

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
}

resource "google_project_iam_member" "roles" {
  for_each = local.sa_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.sa[each.value.sa_key].email}"
}
