#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# GCP Terraform Bootstrap for GitHub Actions + Workload Identity Federation
# -----------------------------------------------------------------------------
# Idempotent bootstrap for:
# - GCS Terraform state bucket
# - Terraform service account
# - Required APIs
# - IAM permissions
# - Workload Identity Pool
# - GitHub OIDC Provider
# - GitHub repository binding to impersonate the Terraform service account
# -----------------------------------------------------------------------------

PROJECT_ID=""
ENVIRONMENT="dev"
REGION="us-central1"
STATE_BUCKET=""
GITHUB_REPO=""
TERRAFORM_SA_ID="sa-terraform"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"
DRY_RUN="false"

usage() {
  cat <<EOF
Usage:
  $0 \
    --project PROJECT_ID \
    --github-repo OWNER/REPO \
    [--env dev] \
    [--region us-central1] \
    [--state-bucket BUCKET_NAME] \
    [--terraform-sa-id sa-terraform] \
    [--pool-id github-pool] \
    [--provider-id github-provider] \
    [--dry-run]

Example:
  $0 \
    --project datalab-project-472519 \
    --github-repo brunogdealmeida/datalab-infra-terraform \
    --env dev \
    --state-bucket datalab-terraform-state
EOF
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="$2"
      shift 2
      ;;
    --env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --state-bucket)
      STATE_BUCKET="$2"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --terraform-sa-id)
      TERRAFORM_SA_ID="$2"
      shift 2
      ;;
    --pool-id)
      POOL_ID="$2"
      shift 2
      ;;
    --provider-id)
      PROVIDER_ID="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${PROJECT_ID}" ]]; then
  echo "ERROR: --project is required."
  usage
  exit 1
fi

if [[ -z "${GITHUB_REPO}" ]]; then
  echo "ERROR: --github-repo is required. Expected format: owner/repository"
  usage
  exit 1
fi

if [[ ! "${GITHUB_REPO}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: --github-repo must use the format owner/repository."
  exit 1
fi

if [[ -z "${STATE_BUCKET}" ]]; then
  STATE_BUCKET="${PROJECT_ID}-terraform-state"
fi

TERRAFORM_SA_EMAIL="${TERRAFORM_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

log "Using project: ${PROJECT_ID}"
log "Using environment: ${ENVIRONMENT}"
log "Using region: ${REGION}"
log "Using state bucket: ${STATE_BUCKET}"
log "Using GitHub repository: ${GITHUB_REPO}"
log "Using Terraform service account: ${TERRAFORM_SA_EMAIL}"
log "Using WIF pool/provider: ${POOL_ID}/${PROVIDER_ID}"

log "Setting active gcloud project..."
run "gcloud config set project '${PROJECT_ID}'"

log "Reading project number..."
if [[ "${DRY_RUN}" == "true" ]]; then
  PROJECT_NUMBER="<PROJECT_NUMBER>"
else
  PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
fi

if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "ERROR: Could not resolve project number for ${PROJECT_ID}."
  exit 1
fi

log "Project number: ${PROJECT_NUMBER}"

log "Enabling required APIs..."
REQUIRED_APIS=(
  "iam.googleapis.com"
  "iamcredentials.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "storage.googleapis.com"
  "sts.googleapis.com"
  "serviceusage.googleapis.com"
  "artifactregistry.googleapis.com"
  "run.googleapis.com"
  "bigquery.googleapis.com"
  "secretmanager.googleapis.com"
  "cloudscheduler.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
  log "Enabling API: ${api}"
  run "gcloud services enable '${api}' --project='${PROJECT_ID}'"
done

log "Creating or reusing Terraform state bucket..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Check/create bucket gs://${STATE_BUCKET}"
else
  if gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    log "Bucket already exists: gs://${STATE_BUCKET}"
  else
    gcloud storage buckets create "gs://${STATE_BUCKET}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --uniform-bucket-level-access
  fi
fi

log "Enabling versioning on state bucket..."
run "gcloud storage buckets update 'gs://${STATE_BUCKET}' --versioning --project='${PROJECT_ID}'"

log "Creating or reusing Terraform service account..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Check/create service account ${TERRAFORM_SA_EMAIL}"
else
  if gcloud iam service-accounts describe "${TERRAFORM_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    log "Service account already exists: ${TERRAFORM_SA_EMAIL}"
  else
    gcloud iam service-accounts create "${TERRAFORM_SA_ID}" \
      --project="${PROJECT_ID}" \
      --display-name="Terraform Service Account"
  fi
fi

log "Granting Terraform service account access to state bucket..."
BUCKET_ROLES=(
  "roles/storage.objectAdmin"
  "roles/storage.legacyBucketReader"
)

for role in "${BUCKET_ROLES[@]}"; do
  log "Granting bucket role ${role}"
  run "gcloud storage buckets add-iam-policy-binding 'gs://${STATE_BUCKET}' \
    --member='serviceAccount:${TERRAFORM_SA_EMAIL}' \
    --role='${role}' \
    --project='${PROJECT_ID}' >/dev/null"
done

log "Granting project roles to Terraform service account..."
PROJECT_ROLES=(
  "roles/serviceusage.serviceUsageAdmin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountUser"
  "roles/iam.workloadIdentityPoolAdmin"
  "roles/artifactregistry.admin"
  "roles/run.admin"
  "roles/bigquery.admin"
  "roles/secretmanager.admin"
  "roles/cloudscheduler.admin"
)

for role in "${PROJECT_ROLES[@]}"; do
  log "Granting project role ${role}"
  run "gcloud projects add-iam-policy-binding '${PROJECT_ID}' \
    --member='serviceAccount:${TERRAFORM_SA_EMAIL}' \
    --role='${role}' \
    --condition=None >/dev/null"
done

log "Creating or reusing Workload Identity Pool..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Check/create WIF pool ${POOL_ID}"
else
  if gcloud iam workload-identity-pools describe "${POOL_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" >/dev/null 2>&1; then
    log "WIF pool already exists: ${POOL_ID}"
  else
    gcloud iam workload-identity-pools create "${POOL_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --display-name="GitHub Actions Pool"
  fi
fi

log "Creating or reusing GitHub OIDC Provider..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Check/create WIF provider ${PROVIDER_ID}"
else
  if gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${POOL_ID}" >/dev/null 2>&1; then
    log "WIF provider already exists: ${PROVIDER_ID}"
  else
    gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
      --project="${PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${POOL_ID}" \
      --display-name="GitHub Provider" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
      --attribute-condition="attribute.repository=='${GITHUB_REPO}'"
  fi
fi

PRINCIPAL_SET="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

log "Granting GitHub repository permission to impersonate Terraform service account..."
run "gcloud iam service-accounts add-iam-policy-binding '${TERRAFORM_SA_EMAIL}' \
  --project='${PROJECT_ID}' \
  --role='roles/iam.workloadIdentityUser' \
  --member='${PRINCIPAL_SET}' >/dev/null"

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

cat <<EOF

================================================================================
BOOTSTRAP COMPLETED
================================================================================

Add these GitHub Actions Variables:

GCP_PROJECT_ID=${PROJECT_ID}
TERRAFORM_SA_EMAIL=${TERRAFORM_SA_EMAIL}
WIF_PROVIDER=${WIF_PROVIDER}

Your Terraform backend config should be:

bucket = "${STATE_BUCKET}"
prefix = "${ENVIRONMENT}"

Do NOT add impersonate_service_account to the backend config when using GitHub WIF.

Next steps:
1. Commit/push your Terraform changes.
2. Add the GitHub Variables above.
3. Run the GitHub Actions workflow with:
   environment = ${ENVIRONMENT}
   action      = plan
4. If the plan succeeds, run:
   environment = ${ENVIRONMENT}
   action      = apply

================================================================================
EOF
