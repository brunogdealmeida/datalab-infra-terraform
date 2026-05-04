#!/usr/bin/env bash
# setup_workload_identity.sh — configures Workload Identity Federation for GitHub Actions.
#
# Run this script once per GCP project, after running bootstrap.sh.
# After it completes, GitHub Actions can authenticate to GCP without any service account key.
#
# Usage:
#   ./bootstrap/setup_workload_identity.sh \
#     --project   my-project-dev \
#     --env       dev \
#     --github-org  my-org \
#     --github-repo my-repo
#
# Required GitHub Actions secrets (add after running this script):
#   WIF_PROVIDER        → output by this script
#   TERRAFORM_SA_EMAIL  → sa-terraform@<project>.iam.gserviceaccount.com

set -euo pipefail

PROJECT_ID=""
ENV=""
GITHUB_ORG=""
GITHUB_REPO=""
SA_NAME="sa-terraform"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT_ID="$2";    shift 2 ;;
    --env)         ENV="$2";           shift 2 ;;
    --github-org)  GITHUB_ORG="$2";   shift 2 ;;
    --github-repo) GITHUB_REPO="$2";  shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

if [[ -z "$PROJECT_ID" || -z "$ENV" || -z "$GITHUB_ORG" || -z "$GITHUB_REPO" ]]; then
  echo "ERROR: --project, --env, --github-org, and --github-repo are all required."
  usage
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

step() { echo; echo "──────────────────────────────────────────"; echo "  $*"; echo "──────────────────────────────────────────"; }
ok()   { echo "  ✓ $*"; }

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")

# ─── 1. Enable required APIs ──────────────────────────────────────────────────

step "1/4  Enabling IAM credentials API"
gcloud services enable iamcredentials.googleapis.com --project="${PROJECT_ID}"
ok "API enabled"

# ─── 2. Create Workload Identity Pool ─────────────────────────────────────────

step "2/4  Creating Workload Identity Pool '${POOL_ID}'"

if gcloud iam workload-identity-pools describe "${POOL_ID}" \
    --location=global --project="${PROJECT_ID}" &>/dev/null; then
  ok "Pool already exists — skipping"
else
  gcloud iam workload-identity-pools create "${POOL_ID}" \
    --location=global \
    --display-name="GitHub Actions Pool" \
    --project="${PROJECT_ID}"
  ok "Pool created"
fi

# ─── 3. Create OIDC Provider for GitHub ──────────────────────────────────────

step "3/4  Creating OIDC provider '${PROVIDER_ID}'"

if gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
    --workload-identity-pool="${POOL_ID}" \
    --location=global --project="${PROJECT_ID}" &>/dev/null; then
  ok "Provider already exists — skipping"
else
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
    --location=global \
    --workload-identity-pool="${POOL_ID}" \
    --display-name="GitHub Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${GITHUB_ORG}/${GITHUB_REPO}'" \
    --project="${PROJECT_ID}"
  ok "Provider created"
fi

# ─── 4. Grant GitHub Actions permission to impersonate sa-terraform ──────────

step "4/4  Binding GitHub Actions → ${SA_EMAIL}"

WIF_PRINCIPAL="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --member="${WIF_PRINCIPAL}" \
  --role="roles/iam.workloadIdentityUser"

ok "Binding created"

# ─── Output ───────────────────────────────────────────────────────────────────

WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo
echo "Setup complete. Add these secrets to your GitHub repository:"
echo "  Settings → Secrets and variables → Actions → New repository secret"
echo
echo "  WIF_PROVIDER        = ${WIF_PROVIDER_FULL}"
echo "  TERRAFORM_SA_EMAIL  = ${SA_EMAIL}"
echo
echo "For the GCS backend bucket, also set these variables (not secrets):"
echo "  Settings → Secrets and variables → Actions → Variables"
echo "  GCP_PROJECT_ID      = ${PROJECT_ID}"
echo
