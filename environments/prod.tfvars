# ─── Project ──────────────────────────────────────────────────────────────────
project_id                = "my-project-prod"
region                    = "us-central1"
environment               = "prod"
terraform_service_account = "sa-terraform@my-project-prod.iam.gserviceaccount.com"

# ─── VPC ─────────────────────────────────────────────────────────────────────
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
    account_id   = "sa-dbt-prod"
    display_name = "DBT Service Account (prod)"
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
    image           = "us-central1-docker.pkg.dev/my-project-prod/datalab-images/dbt:latest"
    cpu             = "4"
    memory          = "4Gi"
    timeout_seconds = 7200
    max_retries     = 2
    service_account = "sa-dbt-prod@my-project-prod.iam.gserviceaccount.com"
    schedule        = "0 6 * * *"
    env_vars = {
      DBT_PROJECT_DIR      = "/dbt"
      DBT_PROFILES_DIR     = "/secrets"
      GOOGLE_CLOUD_PROJECT = "my-project-prod"
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
    dataset_id    = "raw"
    friendly_name = "Raw"
    description   = "Raw ingestion layer"
    location      = "US"
  }
  staging = {
    dataset_id    = "staging"
    friendly_name = "Staging"
    description   = "DBT staging models"
    location      = "US"
  }
  mart = {
    dataset_id    = "mart"
    friendly_name = "Data Mart"
    description   = "Business-ready models"
    location      = "US"
  }
}

# ─── Dataform (optional) ─────────────────────────────────────────────────────
enable_dataform          = false
# dataform_repository_name  = "datalab-dataform"
# dataform_git_remote_url   = "https://github.com/org/dataform-repo.git"
# dataform_git_token_secret = "dataform-git-token"
# dataform_service_account  = "sa-dbt-prod@my-project-prod.iam.gserviceaccount.com"

# ─── Secret Manager ──────────────────────────────────────────────────────────
secrets = {
  dbt-profiles = {
    secret_id = "dbt-profiles-yml"
    accessors = [
      "sa-dbt-prod@my-project-prod.iam.gserviceaccount.com",
    ]
  }
}
