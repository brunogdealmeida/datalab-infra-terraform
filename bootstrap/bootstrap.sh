#!/usr/bin/env bash
# bootstrap.sh — one-time setup for Terraform service account impersonation.
#
# Run this script once per GCP project, as a user with roles/owner.
# After it completes, all Terraform runs use the SA instead of personal credentials.
#
# Usage:
#   ./bootstrap/bootstrap.sh --project my-project-dev --env dev [--caller user:me@example.com]
#
# The --caller flag accepts any IAM member format:
#   user:me@example.com
#   group:devs@example.com
#   serviceAccount:ci-runner@project.iam.gserviceaccount.com
#   principalSet://iam.googleapis.com/...  (Workload Identity)
#
# If --caller is omitted, the currently active gcloud account is used.

set -euo pipefail

# ─── Argument parsing ─────────────────────────────────────────────────────────

PROJECT_ID=""
ENV=""
CALLER=""
SA_NAME="sa-terraform"

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_ID="$2"; shift 2 ;;
    --env)     ENV="$2";        shift 2 ;;
    --caller)  CALLER="$2";     shift 2 ;;
    --sa-name) SA_NAME="$2";    shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

if [[ -z "$PROJECT_ID" || -z "$ENV" ]]; then
  echo "ERROR: --project and --env are required."
  usage
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Default caller to the active gcloud identity
if [[ -z "$CALLER" ]]; then
  ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
  if [[ -z "$ACTIVE_ACCOUNT" ]]; then
    echo "ERROR: no active gcloud account found. Run 'gcloud auth login' first."
    exit 1
  fi
  CALLER="user:${ACTIVE_ACCOUNT}"
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

step() { echo; echo "──────────────────────────────────────────"; echo "  $*"; echo "──────────────────────────────────────────"; }
ok()   { echo "  ✓ $*"; }

# ─── 1. Enable prerequisite APIs ──────────────────────────────────────────────

step "1/5  Enabling prerequisite APIs in project '${PROJECT_ID}'"

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project="${PROJECT_ID}"

ok "APIs enabled"

# ─── 2. Create the Terraform service account ──────────────────────────────────

step "2/5  Creating service account '${SA_EMAIL}'"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  ok "Service account already exists — skipping creation"
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="Terraform Service Account (${ENV})" \
    --project="${PROJECT_ID}"
  ok "Service account created"
fi

# ─── 3. Grant project-level roles to the Terraform SA ─────────────────────────
#
# roles/editor                          — covers most resource CRUD
# roles/iam.serviceAccountAdmin         — create / delete service accounts
# roles/resourcemanager.projectIamAdmin — manage project-level IAM bindings
# roles/iam.securityAdmin               — manage resource-level IAM (secrets, Cloud Run, etc.)
#
# If you prefer a single broad role, replace the four below with:
#   roles/owner
# ─────────────────────────────────────────────────────────────────────────────

step "3/5  Granting IAM roles to '${SA_EMAIL}'"

ROLES=(
  "roles/editor"
  "roles/iam.serviceAccountAdmin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/iam.securityAdmin"
  "roles/cloudbuild.builds.editor"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet
  ok "${ROLE}"
done

# ─── 4. Grant the caller permission to impersonate the SA ─────────────────────

step "4/5  Granting roles/iam.serviceAccountTokenCreator to '${CALLER}'"

gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --member="${CALLER}" \
  --role="roles/iam.serviceAccountTokenCreator"

ok "Impersonation granted"

# ─── 5. Verify impersonation works ────────────────────────────────────────────

step "5/5  Verifying impersonation"

TOKEN=$(gcloud auth print-access-token --impersonate-service-account="${SA_EMAIL}" 2>/dev/null)
if [[ -n "$TOKEN" ]]; then
  ok "Impersonation verified successfully"
else
  echo "  WARNING: could not obtain an impersonation token."
  echo "  IAM changes can take up to 60 seconds to propagate — try again shortly."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo
echo "Bootstrap complete."
echo
echo "Next steps:"
echo "  1. Update environments/${ENV}.tfvars:"
echo "       terraform_service_account = \"${SA_EMAIL}\""
echo
echo "  2. Initialize and apply:"
echo "       make ENV=${ENV} init"
echo "       make ENV=${ENV} plan"
echo "       make ENV=${ENV} apply"
echo
