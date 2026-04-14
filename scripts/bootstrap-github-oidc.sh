#!/usr/bin/env bash
set -euo pipefail

# Bootstrap GitHub OIDC/WIF for this repo.
# Idempotent-ish: create commands may fail if resources already exist; script will continue where safe.

required_cmds=(gcloud)
for c in "${required_cmds[@]}"; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing required command: $c"; exit 1; }
done

# Behavior flags
CREATE_PROJECT="${CREATE_PROJECT:-false}"
TARGET_PROJECT_ID="${TARGET_PROJECT_ID:-sandragon-awx}"

# Required env vars
required_env=(
  GH_ORG
  GH_REPO
  BOOTSTRAP_PROJECT_ID
  WIF_POOL_ID
  WIF_PROVIDER_ID
  DEPLOYER_SA_NAME
  TF_STATE_BUCKET
)

for v in "${required_env[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing required env var: $v"
    exit 1
  fi
done

if [[ "$CREATE_PROJECT" == "true" ]]; then
  if [[ -z "${BILLING_ACCOUNT:-}" ]]; then
    echo "Missing required env var: BILLING_ACCOUNT (required when CREATE_PROJECT=true)"
    exit 1
  fi

  if [[ -n "${ORG_ID:-}" && -n "${FOLDER_ID:-}" ]]; then
    echo "Set only one of ORG_ID or FOLDER_ID (not both) when CREATE_PROJECT=true."
    exit 1
  fi

  if [[ -z "${ORG_ID:-}" && -z "${FOLDER_ID:-}" ]]; then
    echo "Set one of ORG_ID or FOLDER_ID when CREATE_PROJECT=true."
    exit 1
  fi
fi

BOOTSTRAP_PROJECT_NUMBER="${BOOTSTRAP_PROJECT_NUMBER:-$(gcloud projects describe "$BOOTSTRAP_PROJECT_ID" --format='value(projectNumber)')}"
DEPLOYER_SA_EMAIL="${DEPLOYER_SA_EMAIL:-${DEPLOYER_SA_NAME}@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com}"

echo "==> Using bootstrap project: $BOOTSTRAP_PROJECT_ID ($BOOTSTRAP_PROJECT_NUMBER)"
echo "==> Repo: ${GH_ORG}/${GH_REPO}"
echo "==> Deployer SA: $DEPLOYER_SA_EMAIL"

echo "==> Enabling required APIs"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  sts.googleapis.com \
  serviceusage.googleapis.com \
  --project "$BOOTSTRAP_PROJECT_ID"

echo "==> Creating Workload Identity Pool (if missing)"
if ! gcloud iam workload-identity-pools describe "$WIF_POOL_ID" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="global" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$WIF_POOL_ID" \
    --project="$BOOTSTRAP_PROJECT_ID" \
    --location="global" \
    --display-name="GitHub Actions Pool"
else
  echo "Pool already exists: $WIF_POOL_ID"
fi

echo "==> Creating OIDC provider (if missing)"
if ! gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_ID" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$WIF_POOL_ID" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_ID" \
    --project="$BOOTSTRAP_PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$WIF_POOL_ID" \
    --display-name="GitHub Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
    --attribute-condition="attribute.repository=='${GH_ORG}/${GH_REPO}'"
else
  echo "Provider already exists: $WIF_PROVIDER_ID"
fi

echo "==> Creating service account (if missing)"
if ! gcloud iam service-accounts describe "$DEPLOYER_SA_EMAIL" --project "$BOOTSTRAP_PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$DEPLOYER_SA_NAME" \
    --project="$BOOTSTRAP_PROJECT_ID" \
    --display-name="GitHub AWX Deployer"
else
  echo "Service account already exists: $DEPLOYER_SA_EMAIL"
fi

echo "==> Granting workloadIdentityUser on deployer SA"
gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA_EMAIL" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GH_ORG}/${GH_REPO}" >/dev/null

echo "==> Granting bootstrap project roles"
gcloud projects add-iam-policy-binding "$BOOTSTRAP_PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/storage.admin" >/dev/null

gcloud projects add-iam-policy-binding "$BOOTSTRAP_PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator" >/dev/null

if [[ "$CREATE_PROJECT" == "true" ]]; then
  echo "==> Granting projectCreator + billing.user at hierarchy level"
  if [[ -n "${ORG_ID:-}" ]]; then
    gcloud organizations add-iam-policy-binding "$ORG_ID" \
      --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
      --role="roles/resourcemanager.projectCreator" >/dev/null

    gcloud organizations add-iam-policy-binding "$ORG_ID" \
      --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
      --role="roles/billing.user" >/dev/null || true
  else
    gcloud resource-manager folders add-iam-policy-binding "$FOLDER_ID" \
      --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
      --role="roles/resourcemanager.projectCreator" >/dev/null

    gcloud resource-manager folders add-iam-policy-binding "$FOLDER_ID" \
      --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
      --role="roles/billing.user" >/dev/null || true
  fi
else
  echo "==> Skipping org/folder IAM grants (CREATE_PROJECT=false)"
fi

echo "==> Creating state bucket (if missing): gs://${TF_STATE_BUCKET}"
if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="$BOOTSTRAP_PROJECT_ID" \
    --location="us-central1" \
    --uniform-bucket-level-access
else
  echo "Bucket already exists: gs://${TF_STATE_BUCKET}"
fi

echo "==> Enabling bucket versioning"
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning >/dev/null

WIF_PROVIDER_NAME="$(gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_ID" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$WIF_POOL_ID" \
  --format='value(name)')"

cat <<EOF

Bootstrap complete.

Set these GitHub repo secrets:
  GCP_WORKLOAD_IDENTITY_PROVIDER = ${WIF_PROVIDER_NAME}
  GCP_SERVICE_ACCOUNT            = ${DEPLOYER_SA_EMAIL}
  TF_VAR_bootstrap_project_id    = ${BOOTSTRAP_PROJECT_ID}
  TF_STATE_BUCKET                = ${TF_STATE_BUCKET}
  TF_VAR_create_project          = ${CREATE_PROJECT}
  TF_VAR_project_id              = ${TARGET_PROJECT_ID}
  TF_VAR_billing_account         = ${BILLING_ACCOUNT:-}
  TF_VAR_org_id                  = ${ORG_ID:-}
  TF_VAR_folder_id               = ${FOLDER_ID:-}

Note:
- With CREATE_PROJECT=false, ORG_ID/FOLDER_ID and BILLING_ACCOUNT are not required.
- With CREATE_PROJECT=true, roles/billing.user may still need billing-account-level grant by a billing admin.
EOF
