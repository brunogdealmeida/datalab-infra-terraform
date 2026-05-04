output "job_name" {
  description = "Cloud Run Job name."
  value       = google_cloud_run_v2_job.job.name
}

output "job_id" {
  description = "Cloud Run Job full resource ID."
  value       = google_cloud_run_v2_job.job.id
}

output "scheduler_name" {
  description = "Cloud Scheduler job name (null when no schedule is set)."
  value       = one(google_cloud_scheduler_job.scheduler[*].name)
}
