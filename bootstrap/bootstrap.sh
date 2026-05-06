#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# GCP Terraform Bootstrap for GitHub Actions + Workload Identity Federation
# =============================================================================
#
# Purpose:
#   Bootstrap the minimum GCP foundation required for a Terraform CI/CD workflow
#   running from GitHub Actions without service account JSON keys.
#
# Creates or reuses:
#   - Required GCP APIs
#   - Terraform state GCS bucket
#   - Terraform service account
#   - IAM roles for the Terraform service account
#   - Workload Identity Pool
#   - GitHub OIDC Workload Identity Provider
#   - IAM binding allowing the GitHub repo to impersonate the Terraform SA
#
# This script is idempotent and safe to run multiple times.
#
# =============================================================================

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
  ./bootstrap.sh \
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
  ./bootstrap.sh \
    --project datalab-project-472519 \
    --github-repo brunogdealmeida/datalab-infra-terraform \
    --env dev \
    --state-bucket datalab-terraform-state
EOF
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
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
      usage
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command gcloud

[[ -n "${PROJECT_ID}" ]] || fail "--project is required."
[[ -n "${GITHUB_REPO}" ]] || fail "--github-repo is required. Expected format: owner/repository."

if [[ ! "${GITHUB_REPO}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  fail "--github-repo must use the format owner/repository."
fi

if [[ -z "${STATE_BUCKET}" ]]; then
  STATE_BUCKET="${PROJECT_ID}-terraform-state"
fi

TERRAFORM_SA_EMAIL="${TERRAFORM_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

log "Project: ${PROJECT_ID}"
log "Environment: ${ENVIRONMENT}"
log "Region: ${REGION}"
log "State bucket: ${STATE_BUCKET}"
log "GitHub repository: ${GITHUB_REPO}"
log "Terraform service account: ${TERRAFORM_SA_EMAIL}"
log "WIF pool/provider: ${POOL_ID}/${PROVIDER_ID}"

log "Setting active gcloud project..."
run "gcloud config set project '${PROJECT_ID}'"

log "Reading project number..."
if [[ "${DRY_RUN}" == "true" ]]; then
  PROJECT_NUMBER="<PROJECT_NUMBER>"
else
  PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
fi

[[ -n "${PROJECT_NUMBER}" ]] || fail "Could not resolve project number for ${PROJECT_ID}."
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

log "Enabling versioning on Terraform state bucket..."
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
  log "Granting bucket role: ${role}"
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
  log "Granting project role: ${role}"
  run "gcloud projects add-iam-policy-binding '${PROJECT_ID}' \
    --member='serviceAccount:${TERRAFORM_SA_EMAIL}' \
    --role='${role}' \
    --condition=None >/dev/null"
done

log "Checking Workload Identity Pool state..."
if [[ "${DRY_RUN}" == "true" ]]; then
  POOL_STATE=""
  echo "[DRY-RUN] Check WIF pool state: ${POOL_ID}"
else
  POOL_STATE="$(gcloud iam workload-identity-pools describe "${POOL_ID}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --format="value(state)" 2>/dev/null || true)"
fi

if [[ "${POOL_STATE}" == "ACTIVE" ]]; then
  log "WIF pool already exists and is ACTIVE: ${POOL_ID}"
elif [[ "${POOL_STATE}" == "DELETED" ]]; then
  log "WIF pool exists but is DELETED. Undeleting: ${POOL_ID}"
  run "gcloud iam workload-identity-pools undelete '${POOL_ID}' \
    --project='${PROJECT_ID}' \
    --location='global'"
else
  log "Creating WIF pool: ${POOL_ID}"
  run "gcloud iam workload-identity-pools create '${POOL_ID}' \
    --project='${PROJECT_ID}' \
    --location='global' \
    --display-name='GitHub Actions Pool'"
fi

log "Checking GitHub OIDC Provider state..."
if [[ "${DRY_RUN}" == "true" ]]; then
  PROVIDER_STATE=""
  echo "[DRY-RUN] Check WIF provider state: ${PROVIDER_ID}"
else
  PROVIDER_STATE="$(gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_ID}" \
    --format="value(state)" 2>/dev/null || true)"
fi

if [[ "${PROVIDER_STATE}" == "ACTIVE" ]]; then
  log "WIF provider already exists and is ACTIVE: ${PROVIDER_ID}"
elif [[ "${PROVIDER_STATE}" == "DELETED" ]]; then
  log "WIF provider exists but is DELETED. Undeleting: ${PROVIDER_ID}"
  run "gcloud iam workload-identity-pools providers undelete '${PROVIDER_ID}' \
    --project='${PROJECT_ID}' \
    --location='global' \
    --workload-identity-pool='${POOL_ID}'"
else
  log "Creating GitHub OIDC Provider: ${PROVIDER_ID}"
  run "gcloud iam workload-identity-pools providers create-oidc '${PROVIDER_ID}' \
    --project='${PROJECT_ID}' \
    --location='global' \
    --workload-identity-pool='${POOL_ID}' \
    --display-name='GitHub Provider' \
    --issuer-uri='https://token.actions.githubusercontent.com' \
    --attribute-mapping='google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.ref=assertion.ref' \
    --attribute-condition='attribute.repository==\"${GITHUB_REPO}\"'"
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

GitHub Actions Variables:

GCP_PROJECT_ID=${PROJECT_ID}
TERRAFORM_SA_EMAIL=${TERRAFORM_SA_EMAIL}
WIF_PROVIDER=${WIF_PROVIDER}

Terraform backend config:

bucket = "${STATE_BUCKET}"
prefix = "${ENVIRONMENT}"

Important:
- Do not use service account JSON keys.
- Do not add impersonate_service_account to the backend config for this workflow.
- GitHub Actions must authenticate with google-github-actions/auth before terraform init.

Next:
1. Add/update the GitHub Actions variables above.
2. Run GitHub Actions with:
   environment = ${ENVIRONMENT}
   action      = plan
3. If the plan succeeds, run:
   environment = ${ENVIRONMENT}
   action      = apply

================================================================================
EOF
