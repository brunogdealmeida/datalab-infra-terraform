output "vpc_network_name" {
  description = "VPC network name (null when VPC is disabled)."
  value       = one(module.vpc[*].network_name)
}

output "vpc_connector_id" {
  description = "VPC Access Connector full resource ID (null when VPC is disabled)."
  value       = local.vpc_connector_id
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL."
  value       = module.artifact_registry.repository_url
}

output "service_account_emails" {
  description = "Service account emails, keyed by logical name."
  value       = module.iam.service_account_emails
}

output "cloud_run_job_names" {
  description = "Cloud Run Job names, keyed by logical name."
  value       = { for k, job in module.cloud_run_jobs : k => job.job_name }
}

output "bigquery_dataset_ids" {
  description = "BigQuery dataset IDs, keyed by logical name."
  value       = { for k, ds in module.bigquery : k => ds.dataset_id }
}

output "dataform_repository_id" {
  description = "Dataform repository full resource ID (null when Dataform is disabled)."
  value       = one(module.dataform[*].repository_id)
}

output "secret_ids" {
  description = "Secret Manager secret IDs, keyed by logical name."
  value       = { for k, s in module.secrets : k => s.secret_id }
}

