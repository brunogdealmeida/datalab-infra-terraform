resource "google_cloud_run_v2_job" "job" {
  project  = var.project_id
  name     = var.job_name
  location = var.region

  deletion_protection = var.deletion_protection

  template {
    parallelism = var.parallelism
    task_count  = var.task_count

    template {
      service_account = var.runtime_service_account_email
      timeout         = "${var.timeout_seconds}s"
      max_retries     = var.max_retries

      dynamic "volumes" {
        for_each = var.secret_mounts
        content {
          name = volumes.value.volume_name

          secret {
            secret = volumes.value.secret_id

            items {
              version = volumes.value.version
              path    = volumes.value.file_name
            }
          }
        }
      }

      containers {
        image = var.image

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "volume_mounts" {
          for_each = var.secret_mounts
          content {
            name       = volume_mounts.value.volume_name
            mount_path = volume_mounts.value.mount_path
          }
        }
      }

      dynamic "vpc_access" {
        for_each = var.vpc_connector != null && var.vpc_connector != "" ? [1] : []
        content {
          connector = var.vpc_connector
          egress    = "PRIVATE_RANGES_ONLY"
        }
      }
    }
  }
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  count = var.schedule != "" ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.job.name

  role   = "roles/run.invoker"
  member = "serviceAccount:${var.scheduler_service_account_email}"
}

resource "google_cloud_scheduler_job" "scheduler" {
  count = var.schedule != "" ? 1 : 0

  project          = var.project_id
  name             = "${var.job_name}-scheduler"
  region           = var.region
  schedule         = var.schedule
  time_zone        = var.time_zone
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.job.name}:run"

    oauth_token {
      service_account_email = var.scheduler_service_account_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_cloud_run_v2_job.job,
    google_cloud_run_v2_job_iam_member.scheduler_invoker
  ]
}