output "pool_name" {
  description = "Full resource name of the Workload Identity Pool."
  value       = google_iam_workload_identity_pool.pool.name
}

output "provider_name" {
  description = "Full resource name of the Workload Identity Pool Provider."
  value       = google_iam_workload_identity_pool_provider.provider.name
}

output "provider_resource_path" {
  description = "WIF provider resource path to use as the WIF_PROVIDER GitHub Actions secret."
  value       = "projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${var.pool_id}/providers/${var.provider_id}"
}
