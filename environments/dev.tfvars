# ─── Project ──────────────────────────────────────────────────────────────────
project_id                = "datalab-project-472519"
region                    = "us-central1"
environment               = "dev"
terraform_service_account = "sa-terraform@datalab-project-472519.iam.gserviceaccount.com"

# ─── Workload Identity Federation ────────────────────────────────────────────
github_repository = "brunogdealmeida/datalab-infra-gcp"

# ─── VPC (optional — set enable_vpc = true to create networking resources) ───
enable_vpc = false
# vpc_name           = "datalab-vpc"
# subnet_ip_range    = "10.0.0.0/24"
# connector_ip_range = "10.8.0.0/28"

# ─── Artifact Registry ────────────────────────────────────────────────────────
repository_id          = "datalab-images"
repository_format      = "DOCKER"
repository_description = "Docker images for data platform jobs"

# ─── IAM / Service Accounts ──────────────────────────────────────────────────
service_accounts = {
  dbt = {
    account_id   = "sa-dbt-dev"
    display_name = "DBT Service Account (dev)"
    roles = [
      "roles/bigquery.jobUser",
      "roles/bigquery.dataEditor",
      "roles/bigquery.dataOwner",
      "roles/artifactregistry.reader",
      "roles/secretmanager.secretAccessor",
      "roles/run.invoker",
    ]
  }
}

# ─── Docker Builds ───────────────────────────────────────────────────────────
# Terraform builds and pushes the image automatically before creating Cloud Run Jobs.
docker_builds = {
  dbt = {
    context_path = "./dbt"
    image_tag    = "latest"
  }
}

# ─── Cloud Run Jobs ──────────────────────────────────────────────────────────
cloud_run_jobs = {
  "dbt-run" = {
    image           = "us-central1-docker.pkg.dev/datalab-project-472519/datalab-images/dbt:latest"
    cpu             = "1"
    memory          = "1Gi"
    timeout_seconds = 3600
    max_retries     = 1
    parallelism     = 1
    task_count      = 1
    service_account = "sa-dbt-dev@datalab-project-472519.iam.gserviceaccount.com"
    schedule        = "0 6 * * *"

    env_vars = {
      DBT_PROJECT_DIR      = "/dbt"
      DBT_PROFILES_DIR     = "/secrets"
      GOOGLE_CLOUD_PROJECT = "datalab-project-472519"
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
    dataset_id    = "raw_dev"
    friendly_name = "Raw (dev)"
    description   = "Raw ingestion layer"
    location      = "US"
    access = [
      { role = "OWNER", special_group = "projectOwners" },
      { role = "WRITER", user_by_email = "sa-dbt-dev@datalab-project-472519.iam.gserviceaccount.com" },
    ]
  }
  staging = {
    dataset_id    = "staging_dev"
    friendly_name = "Staging (dev)"
    description   = "DBT staging models"
    location      = "US"
  }
  mart = {
    dataset_id    = "mart_dev"
    friendly_name = "Data Mart (dev)"
    description   = "Business-ready models"
    location      = "US"
  }
}

# ─── Dataform (optional) ─────────────────────────────────────────────────────
enable_dataform = false
# dataform_repository_name  = "datalab-dataform"
# dataform_git_remote_url   = "https://github.com/org/dataform-repo.git"
# dataform_git_token_secret = "dataform-git-token"
# dataform_default_branch   = "main"
# dataform_service_account  = "sa-dbt-dev@datalab-project-472519.iam.gserviceaccount.com"

# ─── Secret Manager ──────────────────────────────────────────────────────────
# secret_data is loaded from a local file so no manual gcloud step is needed.
# The file must exist before running terraform apply.
# NEVER commit files under secrets/ — they are git-ignored.
secrets = {
  dbt-profiles = {
    secret_id   = "dbt-profiles-yml"
    secret_file = "secrets/dev/profiles.yml"
    accessors = [
      "sa-dbt-dev@datalab-project-472519.iam.gserviceaccount.com",
    ]
  }
}
