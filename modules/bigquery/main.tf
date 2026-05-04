resource "google_bigquery_dataset" "dataset" {
  project                    = var.project_id
  dataset_id                 = var.dataset_id
  friendly_name              = var.friendly_name != "" ? var.friendly_name : null
  description                = var.description != "" ? var.description : null
  location                   = var.location
  delete_contents_on_destroy = var.delete_contents_on_destroy

  dynamic "access" {
    for_each = var.access
    content {
      role           = access.value.role
      user_by_email  = access.value.user_by_email
      group_by_email = access.value.group_by_email
      special_group  = access.value.special_group
      iam_member     = access.value.iam_member
    }
  }
}
