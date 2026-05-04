output "service_account_emails" {
  description = "Map of logical name to service account email."
  value = {
    for key, sa in google_service_account.sa :
    key => sa.email
  }
}

output "service_account_ids" {
  description = "Map of logical name to service account ID."
  value = {
    for key, sa in google_service_account.sa :
    key => sa.account_id
  }
}
