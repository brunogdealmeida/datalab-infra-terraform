# datalab-infra-gcp - 1.0

Terraform project for the Data Lab GCP infrastructure. Manages Cloud Run Jobs (DBT), BigQuery datasets, Dataform, Artifact Registry, Secret Manager, IAM, and an optional private VPC — all parameterized per environment.

---

## Table of contents

1. [Architecture overview](#architecture-overview)
2. [Project structure](#project-structure)
3. [Modules](#modules)
4. [Prerequisites](#prerequisites)
5. [Authentication and impersonation](#authentication-and-impersonation)
6. [How to run](#how-to-run)
7. [Environment configuration](#environment-configuration)
8. [Optional features](#optional-features)
9. [Adding resources](#adding-resources)
10. [Outputs](#outputs)
11. [Design decisions](#design-decisions)

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  GCP Project                                                                │
│                                                                             │
│  ┌──────────────────────┐    triggers     ┌──────────────────────────────┐  │
│  │   Cloud Scheduler    │────────────────▶│     Cloud Run Job (DBT)      │  │
│  │  (cron, optional)    │                 │                              │  │
│  └──────────────────────┘                 │  ┌────────────────────────┐  │  │
│                                           │  │  Secret Mount          │  │  │
│                                           │  │  /secrets/profiles.yml │  │  │
│                                           │  └─────────┬──────────────┘  │  │
│                                           └────────────┼─────────────────┘  │
│                                                        │                    │
│  ┌─────────────────────────────────────────────────────▼──────────────┐    │
│  │  Secret Manager                                                     │    │
│  │  • dbt-profiles-yml   • dataform-git-token   • (any secret)        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  BigQuery                                                            │   │
│  │  ┌───────────┐   ┌───────────┐   ┌───────────┐                      │   │
│  │  │    raw    │   │  staging  │   │   mart    │   (any dataset)      │   │
│  │  └───────────┘   └───────────┘   └───────────┘                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌────────────────────┐   ┌─────────────────────┐   ┌──────────────────┐   │
│  │  Artifact Registry │   │      Dataform        │   │       IAM        │   │
│  │  (Docker images)   │   │  (optional Git repo) │   │  Service Accounts│   │
│  └────────────────────┘   └─────────────────────┘   └──────────────────┘   │
│                                                                             │
│  ┌──────────────────────────────────── VPC (optional) ─────────────────┐   │
│  │  ┌──────────────┐   ┌──────────────────┐   ┌─────────────────────┐  │   │
│  │  │    Subnet    │   │  VPC Connector   │   │    Cloud NAT        │  │   │
│  │  │  10.0.0.0/24 │   │  (Serverless)    │   │  (egress to GCP)   │  │   │
│  │  └──────────────┘   └──────────────────┘   └─────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data flow

1. **Cloud Scheduler** fires a cron trigger at the configured interval.
2. It calls the **Cloud Run Jobs** API via HTTP POST using OAuth (service account token).
3. The **Cloud Run Job** runs the DBT container image pulled from **Artifact Registry**.
4. DBT reads `profiles.yml` from a **Secret Manager** secret mounted as a file at `/secrets/profiles.yml`.
5. DBT connects to **BigQuery** and materializes models across `raw → staging → mart` datasets.
6. *(Optional)* **Dataform** can complement or replace DBT for SQL workflow orchestration, connecting to BigQuery using its own service account.
7. *(Optional)* When **VPC** is enabled, the Cloud Run Job egresses through the **VPC Access Connector**, isolating network traffic inside the private subnet.

---

## Project structure

```
datalab-infra-gcp/
├── terraform.tf              # Provider + partial GCS backend declaration
├── main.tf                   # Root orchestration: API enablement + module calls
├── variables.tf              # All root-level input variables
├── outputs.tf                # Root-level outputs
├── terraform.tfvars          # Intentionally empty — use environments/ instead
├── Makefile                  # Convenience targets (init / plan / apply / destroy)
│
├── environments/
│   ├── dev.tfvars            # Dev variable values
│   ├── dev.tfbackend         # Dev remote state config (GCS bucket + prefix)
│   ├── staging.tfvars
│   ├── staging.tfbackend
│   ├── prod.tfvars
│   └── prod.tfbackend
│
└── modules/
    ├── vpc/                  # VPC network, subnet, VPC Access Connector, NAT
    ├── artifact_registry/    # Artifact Registry repository
    ├── iam/                  # Service accounts + project IAM bindings
    ├── cloud_run_job/        # Cloud Run v2 Job + Cloud Scheduler + IAM invoker
    ├── bigquery/             # BigQuery dataset with access control
    ├── dataform/             # Dataform repository + service account IAM
    └── secret_manager/       # Secret Manager secret + version + accessor IAM
```

---

## Modules

### `modules/vpc`

Creates a private network for workloads that need network isolation.

| Resource | Description |
|---|---|
| `google_compute_network` | VPC network (no auto subnets) |
| `google_compute_subnetwork` | Primary subnet with Private Google Access enabled |
| `google_vpc_access_connector` | Serverless VPC Access Connector for Cloud Run |
| `google_compute_router` | Cloud Router (required for NAT) |
| `google_compute_router_nat` | Cloud NAT for outbound internet access |

**Private Google Access** allows Cloud Run Jobs to reach BigQuery and Secret Manager without routing traffic to the public internet, even when NAT is not used.

| Variable | Default | Description |
|---|---|---|
| `vpc_name` | — | Network name |
| `subnet_ip_range` | `10.0.0.0/24` | Primary subnet CIDR |
| `connector_ip_range` | `10.8.0.0/28` | VPC Access Connector CIDR (must be /28) |

---

### `modules/artifact_registry`

Stores Docker images built for DBT or other jobs.

| Variable | Default | Description |
|---|---|---|
| `repository_id` | — | Repository name |
| `format` | `DOCKER` | `DOCKER`, `PYTHON`, `NPM`, etc. |
| `description` | `""` | Optional description |

**Output:** `repository_url` — the full URL to use with `docker push`, e.g. `us-central1-docker.pkg.dev/project/repo`.

---

### `modules/iam`

Creates service accounts and assigns project-level IAM roles.

Accepts a **map** of service accounts so multiple identities can be declared in one block:

```hcl
service_accounts = {
  dbt = {
    account_id   = "sa-dbt-prod"
    display_name = "DBT Service Account"
    roles = [
      "roles/bigquery.jobUser",
      "roles/bigquery.dataEditor",
      "roles/secretmanager.secretAccessor",
      "roles/run.invoker",
    ]
  }
}
```

**Output:** `service_account_emails` — map of logical name → email, e.g. `{ dbt = "sa-dbt-prod@project.iam.gserviceaccount.com" }`.

---

### `modules/cloud_run_job`

Creates a **Cloud Run v2 Job** with optional scheduling and secret file mounts.

| Variable | Default | Description |
|---|---|---|
| `image` | — | Container image URL |
| `cpu` | `"1"` | vCPU (e.g. `"1"`, `"2"`, `"4"`) |
| `memory` | `"512Mi"` | Memory (e.g. `"1Gi"`, `"4Gi"`) |
| `timeout_seconds` | `3600` | Max task duration |
| `max_retries` | `0` | Retries on failure |
| `service_account` | `""` | SA email to run the job as |
| `schedule` | `""` | Cron expression — empty disables Cloud Scheduler |
| `vpc_connector` | `""` | VPC Connector ID — empty skips VPC attachment |
| `env_vars` | `{}` | Environment variables map |
| `secret_mounts` | `[]` | Secret Manager files to mount (see below) |

**Secret mounts** mount a Secret Manager secret as a file inside the container:

```hcl
secret_mounts = [
  {
    volume_name = "dbt-profiles"     # internal volume identifier
    secret_id   = "dbt-profiles-yml" # Secret Manager secret ID
    version     = "latest"           # secret version
    mount_path  = "/secrets"         # directory inside the container
    file_name   = "profiles.yml"     # file name inside that directory
  }
]
# Result: the secret value appears at /secrets/profiles.yml inside the container
```

When `schedule` is non-empty, two additional resources are created:
- `google_cloud_scheduler_job` — calls the Cloud Run Jobs API via HTTP POST on the cron schedule
- `google_cloud_run_v2_job_iam_member` — grants `roles/run.invoker` to the service account so the scheduler can trigger the job

---

### `modules/bigquery`

Creates a BigQuery dataset with configurable access control entries.

```hcl
bigquery_datasets = {
  raw = {
    dataset_id = "raw_dev"
    location   = "US"
    access = [
      { role = "OWNER",  special_group = "projectOwners" },
      { role = "WRITER", user_by_email = "sa-dbt@project.iam.gserviceaccount.com" },
    ]
  }
}
```

| Variable | Default | Description |
|---|---|---|
| `dataset_id` | — | BigQuery dataset ID |
| `location` | `"US"` | Multi-region (`US`, `EU`) or region |
| `delete_contents_on_destroy` | `false` | Safety guard — set `true` only in dev |
| `access` | `[]` | IAM access entries |

---

### `modules/dataform`

Creates a Dataform repository optionally connected to a Git remote.

```hcl
enable_dataform          = true
dataform_repository_name  = "datalab-dataform"
dataform_git_remote_url   = "https://github.com/org/repo.git"
dataform_git_token_secret = "dataform-git-token"   # Secret Manager secret ID
dataform_service_account  = "sa-dbt@project.iam.gserviceaccount.com"
```

When `service_account` is set, the module grants it:
- `roles/bigquery.dataEditor`
- `roles/bigquery.jobUser`
- `roles/secretmanager.secretAccessor`

---

### `modules/secret_manager`

Creates a Secret Manager secret with optional initial value and accessor IAM bindings.

```hcl
secrets = {
  dbt-profiles = {
    secret_id   = "dbt-profiles-yml"
    # secret_data = ""   # leave empty and set the value manually
    accessors   = ["sa-dbt@project.iam.gserviceaccount.com"]
  }
}
```

Leave `secret_data` empty to manage the secret value outside Terraform (recommended for production credentials). The resource and IAM bindings are still created — only the secret version is skipped.

---

## Authentication and impersonation

### How it works

Every `terraform plan` and `terraform apply` runs as a dedicated **Terraform service account** (`sa-terraform@<project>.iam.gserviceaccount.com`) rather than as your personal Google account. Your personal account (or CI runner) only needs one IAM role — `roles/iam.serviceAccountTokenCreator` on that service account — and never holds any resource-level permissions directly.

```
┌─────────────────────┐    Token Creator     ┌──────────────────────────┐
│  You / CI runner    │ ────────────────────▶ │   sa-terraform@project   │
│  (ADC / OIDC token) │   impersonates        │                          │
└─────────────────────┘                       │  roles/editor            │
                                              │  roles/iam.sa.Admin      │
         Terraform uses the SA token ◀────────│  roles/proj.iamAdmin     │
         to call all GCP APIs                 │  roles/iam.securityAdmin │
                                              └──────────────────────────┘
```

**Why impersonation instead of a key file?**

| Approach | Key file | Impersonation |
|---|---|---|
| Long-lived credential at rest | Yes — file on disk | No — short-lived token (1 h) |
| Rotation required | Yes | No |
| Audit trail | Hard to attribute | Full Cloud Audit Log per caller |
| CI secret management | Key stored as CI secret | Only OIDC token needed |

### One-time bootstrap

Run the bootstrap script **once per project**, as a user with `roles/owner`:

```bash
# Authenticate as yourself first
gcloud auth login
gcloud auth application-default login

# Run bootstrap (creates SA, grants roles, grants you impersonation)
./bootstrap/bootstrap.sh \
  --project my-project-dev \
  --env     dev \
  --caller  user:your-email@example.com
```

**What the script does:**

1. Enables `iamcredentials.googleapis.com` (required for impersonation API)
2. Creates `sa-terraform@<project>.iam.gserviceaccount.com`
3. Grants it the four roles needed to manage all project resources:
   - `roles/editor` — resource CRUD
   - `roles/iam.serviceAccountAdmin` — create/delete service accounts
   - `roles/resourcemanager.projectIamAdmin` — project-level IAM bindings
   - `roles/iam.securityAdmin` — resource-level IAM (secrets, Cloud Run jobs, etc.)
4. Grants **you** `roles/iam.serviceAccountTokenCreator` on the SA
5. Verifies impersonation works end-to-end

Repeat for each environment (change `--project` and `--env`). The script is idempotent — safe to run multiple times.

### Adding more callers

To allow a colleague or a CI service account to impersonate:

```bash
# Another human
gcloud iam service-accounts add-iam-policy-binding \
  sa-terraform@my-project-dev.iam.gserviceaccount.com \
  --project=my-project-dev \
  --member="user:colleague@example.com" \
  --role="roles/iam.serviceAccountTokenCreator"

# GitHub Actions via Workload Identity Federation
gcloud iam service-accounts add-iam-policy-binding \
  sa-terraform@my-project-dev.iam.gserviceaccount.com \
  --project=my-project-dev \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/attribute.repository/org/repo" \
  --role="roles/iam.serviceAccountTokenCreator"
```

### Configuring the provider

The `impersonate_service_account` is set via the `terraform_service_account` variable, which every environment tfvars already includes:

```hcl
# environments/dev.tfvars
terraform_service_account = "sa-terraform@my-project-dev.iam.gserviceaccount.com"
```

Set it to `""` to fall back to Application Default Credentials without impersonation (useful for local experimentation only).

### CI/CD (GitHub Actions example)

```yaml
- name: Authenticate to GCP
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID
    service_account: ci-runner@my-project-prod.iam.gserviceaccount.com

- name: Terraform plan
  run: |
    make ENV=prod init
    make ENV=prod plan
```

The CI runner SA (`ci-runner@...`) only needs `roles/iam.serviceAccountTokenCreator` on `sa-terraform@...`. All actual GCP permissions stay on the Terraform SA.

---

## Prerequisites

| Tool | Minimum version |
|---|---|
| Terraform | >= 1.3.0 |
| Google Cloud SDK (`gcloud`) | Any recent version |
| GCP project with billing enabled | — |

**Permissions required** to run `terraform apply`:

- `roles/owner` on the project, or a custom role with at minimum:
  - `resourcemanager.projects.setIamPolicy`
  - `serviceusage.services.enable`
  - `iam.serviceAccounts.create`
  - Service-specific admin roles for each resource type

**GCS bucket for remote state** must exist before the first `init`. Create it once:

```bash
gcloud storage buckets create gs://datalab-terraform-state \
  --project=YOUR_PROJECT_ID \
  --location=us-central1 \
  --uniform-bucket-level-access
```

---

## How to run

### 1. Authenticate

```bash
gcloud auth application-default login
```

### 2. Configure your environment

Edit `environments/dev.tfvars` and replace the placeholder values:

```hcl
project_id  = "your-actual-project-id"
region      = "us-central1"
environment = "dev"
```

Update `environments/dev.tfbackend` with your state bucket:

```hcl
bucket = "your-terraform-state-bucket"
prefix = "dev"
```

### 3. Initialize

```bash
make ENV=dev init
# Equivalent to:
# terraform init -backend-config=environments/dev.tfbackend -reconfigure
```

### 4. Plan

```bash
make ENV=dev plan
# Equivalent to:
# terraform plan -var-file=environments/dev.tfvars
```

Review the plan output carefully before proceeding.

### 5. Apply

```bash
make ENV=dev apply
# Equivalent to:
# terraform apply -var-file=environments/dev.tfvars
```

### 6. Destroy (when needed)

```bash
make ENV=dev destroy
```

### Other targets

```bash
make fmt        # Format all .tf files recursively
make validate   # Validate configuration syntax
```

### Switching environments

```bash
make ENV=staging init
make ENV=staging plan
make ENV=staging apply

make ENV=prod init
make ENV=prod plan
make ENV=prod apply
```

Each environment has isolated remote state via its own GCS prefix (`dev`, `staging`, `prod`).

---

## Environment configuration

All environment differences live in `environments/<env>.tfvars`. Nothing environment-specific is hardcoded in the modules or root files.

| File | Purpose |
|---|---|
| `environments/dev.tfvars` | Dev project, smaller resources, VPC disabled, no schedule |
| `environments/staging.tfvars` | Staging project, medium resources, VPC enabled, scheduled |
| `environments/prod.tfvars` | Prod project, larger resources, VPC enabled, scheduled |
| `environments/<env>.tfbackend` | GCS bucket + prefix for that environment's state |

**Typical differences between environments:**

| Setting | dev | staging | prod |
|---|---|---|---|
| `enable_vpc` | `false` | `true` | `true` |
| `cpu` / `memory` | `1` / `1Gi` | `2` / `2Gi` | `4` / `4Gi` |
| `schedule` | *(empty)* | `"0 7 * * *"` | `"0 6 * * *"` |
| Dataset IDs | `raw_dev`, `staging_dev` | `raw_staging` | `raw`, `staging` |
| `delete_contents_on_destroy` | `true` | `false` | `false` |

---

## Optional features

### Enable VPC

Set in your `.tfvars`:

```hcl
enable_vpc         = true
vpc_name           = "datalab-vpc"
subnet_ip_range    = "10.0.0.0/24"
connector_ip_range = "10.8.0.0/28"
```

When enabled, Cloud Run Jobs are automatically attached to the VPC via the Access Connector. Cloud NAT is created so jobs can still reach the internet when needed.

> The VPC connector CIDR (`connector_ip_range`) must be a `/28` and must not overlap with the subnet or any other range in your network.

### Enable Dataform

```hcl
enable_dataform          = true
dataform_repository_name  = "datalab-dataform"
dataform_git_remote_url   = "https://github.com/org/repo.git"
dataform_git_token_secret = "dataform-git-token"
dataform_service_account  = "sa-dbt-dev@my-project-dev.iam.gserviceaccount.com"
```

Store the Git personal access token in Secret Manager first:

```bash
echo -n "ghp_your_token_here" | gcloud secrets create dataform-git-token \
  --data-file=- \
  --project=YOUR_PROJECT_ID
```

### Enable Cloud Scheduler for a job

Add a `schedule` to any job in `cloud_run_jobs`:

```hcl
cloud_run_jobs = {
  dbt-run = {
    ...
    schedule = "0 6 * * *"   # daily at 06:00 UTC
  }
}
```

Terraform will automatically enable the `cloudscheduler.googleapis.com` API and create the scheduler resource.

---

## Adding resources

### Add a new Cloud Run Job

In your `.tfvars`, add a key to `cloud_run_jobs`:

```hcl
cloud_run_jobs = {
  dbt-run = { ... }   # existing

  dbt-full-refresh = {
    image           = "us-central1-docker.pkg.dev/my-project/datalab-images/dbt:latest"
    cpu             = "4"
    memory          = "4Gi"
    timeout_seconds = 14400
    service_account = "sa-dbt-prod@my-project.iam.gserviceaccount.com"
    schedule        = "0 2 * * 0"   # weekly on Sunday at 02:00 UTC
    env_vars = {
      DBT_TARGET   = "prod"
      DBT_FULL_REFRESH = "true"
    }
  }
}
```

No module changes required — `for_each` on the module creates one Cloud Run Job per map entry.

### Add a new BigQuery dataset

```hcl
bigquery_datasets = {
  raw     = { ... }   # existing
  staging = { ... }   # existing
  mart    = { ... }   # existing

  metrics = {
    dataset_id    = "metrics_dev"
    friendly_name = "Metrics"
    description   = "Aggregated business metrics"
    location      = "US"
  }
}
```

### Add a new secret

```hcl
secrets = {
  dbt-profiles = { ... }   # existing

  bq-service-account-key = {
    secret_id = "bq-sa-key"
    accessors = ["sa-dbt-dev@my-project-dev.iam.gserviceaccount.com"]
  }
}
```

Then set the value manually:

```bash
gcloud secrets versions add bq-sa-key \
  --data-file=path/to/key.json \
  --project=YOUR_PROJECT_ID
```

### Add a new service account

```hcl
service_accounts = {
  dbt = { ... }   # existing

  dataform = {
    account_id   = "sa-dataform-dev"
    display_name = "Dataform Service Account (dev)"
    roles = [
      "roles/bigquery.jobUser",
      "roles/bigquery.dataEditor",
      "roles/secretmanager.secretAccessor",
    ]
  }
}
```

---

## Outputs

After `terraform apply`, view all outputs:

```bash
terraform output
```

| Output | Description |
|---|---|
| `artifact_registry_url` | Full Docker repository URL for `docker push` |
| `service_account_emails` | Map of logical name → service account email |
| `cloud_run_job_names` | Map of logical name → Cloud Run Job name |
| `bigquery_dataset_ids` | Map of logical name → BigQuery dataset ID |
| `vpc_connector_id` | VPC Access Connector resource ID (null if VPC disabled) |
| `vpc_network_name` | VPC network name (null if VPC disabled) |
| `dataform_repository_id` | Dataform repository resource ID (null if disabled) |
| `secret_ids` | Map of logical name → Secret Manager secret ID |

---

## Design decisions

**Service account impersonation instead of key files**
Terraform authenticates via short-lived tokens generated by impersonating a dedicated `sa-terraform` service account. No key file ever touches disk. The calling identity (human or CI runner) only needs `roles/iam.serviceAccountTokenCreator` on the SA — it holds no GCP resource permissions of its own. This creates a clear audit trail and eliminates long-lived credential rotation.

**Single root, multiple environments via `-var-file`**
Rather than duplicating the root module per environment (a common but brittle pattern), all environments share one codebase. Environment differences live exclusively in `environments/<env>.tfvars`. This means a change to a module is immediately testable in dev and promotable to prod without copy-pasting.

**Partial backend configuration**
Terraform does not allow variables in `backend {}` blocks. The `backend "gcs" {}` block is intentionally empty; the actual bucket and prefix are injected at `init` time via `-backend-config=environments/<env>.tfbackend`. This keeps state isolated per environment without requiring separate root modules.

**`optional()` type constraints (Terraform >= 1.3)**
Complex variables like `cloud_run_jobs` use `optional(type, default)` inside `object()`. This lets callers omit fields they don't need while keeping a strict, self-documenting schema — no silent `null` surprises.

**`for_each` on modules**
Cloud Run Jobs, BigQuery datasets, and secrets use `for_each` on the module call. Adding or removing a resource is a one-line change in the tfvars file — no HCL edits required in the module or root.

**VPC is opt-in**
Many GCP services (BigQuery, Secret Manager, Artifact Registry) are reachable via Private Google Access without a VPC. VPC isolation adds operational cost and complexity. The default is `enable_vpc = false` so development environments stay simple, and production can enable it when compliance or security policies require it.

**APIs are auto-enabled**
`google_project_service` resources in `main.tf` enable only the APIs that are actually needed based on which features are toggled on. `disable_on_destroy = false` prevents accidental API disablement (which would break all resources using that API) when running `terraform destroy`.

**`secret_data` is optional**
Storing secret values in Terraform state is discouraged for production credentials. The `secret_manager` module creates the secret and IAM bindings regardless, but only creates a secret version when `secret_data` is non-empty. Credentials are set separately via `gcloud secrets versions add` or the GCP Console.
