output "secret_id" {
  description = "Secret Manager secret ID."
  value       = google_secret_manager_secret.secret.secret_id
}

output "secret_name" {
  description = "Full secret resource name."
  value       = google_secret_manager_secret.secret.name
}

output "secret_version" {
  description = "Latest managed secret version resource name (null if secret_data is empty)."
  value       = one(google_secret_manager_secret_version.version[*].name)
}
