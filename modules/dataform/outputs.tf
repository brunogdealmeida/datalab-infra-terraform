output "repository_id" {
  description = "Dataform repository full resource ID."
  value       = google_dataform_repository.repo.id
}

output "repository_name" {
  description = "Dataform repository name."
  value       = google_dataform_repository.repo.name
}
