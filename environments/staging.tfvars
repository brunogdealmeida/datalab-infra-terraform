# ─── Project ──────────────────────────────────────────────────────────────────
project_id                = "my-project-staging"
region                    = "us-central1"
environment               = "staging"

# ─── VPC (optional) ──────────────────────────────────────────────────────────
enable_vpc         = true
vpc_name           = "datalab-vpc"
subnet_ip_range    = "10.0.0.0/24"
connector_ip_range = "10.8.0.0/28"

# ─── Artifact Registry ────────────────────────────────────────────────────────
repository_id     = "datalab-images"
repository_format = "DOCKER"

# ─── IAM / Service Accounts ──────────────────────────────────────────────────
service_accounts = {
  dbt = {
    account_id   = "sa-dbt-staging"
    display_name = "DBT Service Account (staging)"
    roles = [
      "roles/bigquery.jobUser",
      "roles/bigquery.dataEditor",
      "roles/artifactregistry.reader",
      "roles/secretmanager.secretAccessor",
      "roles/run.invoker",
    ]
  }
}

# ─── Cloud Run Jobs ──────────────────────────────────────────────────────────
cloud_run_jobs = {
  dbt-run = {
    image           = "us-central1-docker.pkg.dev/my-project-staging/datalab-images/dbt:latest"
    cpu             = "2"
    memory          = "2Gi"
    timeout_seconds = 3600
    max_retries     = 1
    service_account = "sa-dbt-staging@my-project-staging.iam.gserviceaccount.com"
    schedule        = "0 7 * * *"
    env_vars = {
      DBT_PROJECT_DIR      = "/dbt"
      DBT_PROFILES_DIR     = "/secrets"
      GOOGLE_CLOUD_PROJECT = "my-project-staging"
    }
    secret_mounts = [
      {
        volume_name = "dbt-profiles"
        secret_id   = "dbt-profiles-yml"
        version     = "latest"
        mount_path  = "/secrets"
        file_name   = "profiles.yml"
      }
    ]
  }
}

# ─── BigQuery ────────────────────────────────────────────────────────────────
bigquery_datasets = {
  raw = {
    dataset_id = "raw_staging"
    location   = "US"
  }
  staging = {
    dataset_id = "staging_staging"
    location   = "US"
  }
  mart = {
    dataset_id = "mart_staging"
    location   = "US"
  }
}

# ─── Dataform (optional) ─────────────────────────────────────────────────────
enable_dataform = false

# ─── Secret Manager ──────────────────────────────────────────────────────────
secrets = {
  dbt-profiles = {
    secret_id = "dbt-profiles-yml"
    accessors = [
      "sa-dbt-staging@my-project-staging.iam.gserviceaccount.com",
    ]
  }
}
