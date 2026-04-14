# Bootstrap checklist: GitHub Actions OIDC for GCP

This guide bootstraps keyless GitHub Actions auth (OIDC/WIF) and the minimum setup needed for this repo workflows.

Assumptions:
- GitHub repo: `YOUR_GH_ORG/awx-gke`
- Existing bootstrap project for identity/state resources
- Target project to be created by OpenTofu: `sandragon-awx`

---

## 0) Set environment variables (edit first)

```bash
# ---- REQUIRED: edit me ----
export GH_ORG="YOUR_GH_ORG"
export GH_REPO="awx-gke"

export BOOTSTRAP_PROJECT_ID="your-bootstrap-project-id"   # existing project
export BOOTSTRAP_PROJECT_NUMBER="$(gcloud projects describe "$BOOTSTRAP_PROJECT_ID" --format='value(projectNumber)')"

export BILLING_ACCOUNT="000000-000000-000000"
export ORG_ID="123456789012"          # use this OR folder below
export FOLDER_ID=""                   # set this instead of ORG_ID if needed

# OIDC pool/provider naming
export WIF_POOL_ID="github-pool"
export WIF_PROVIDER_ID="github-provider"

# Service account used by GitHub Actions
export DEPLOYER_SA_NAME="github-awx-deployer"
export DEPLOYER_SA_EMAIL="${DEPLOYER_SA_NAME}@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"

# State bucket
export TF_STATE_BUCKET="${BOOTSTRAP_PROJECT_ID}-tofu-state-awx"
```

> Use exactly one of `ORG_ID` or `FOLDER_ID` for Terraform inputs.

---

## 1) Enable required APIs in bootstrap project

```bash
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  sts.googleapis.com \
  serviceusage.googleapis.com \
  --project "$BOOTSTRAP_PROJECT_ID"
```

---

## 2) Create Workload Identity Pool + Provider (GitHub OIDC)

```bash
# Create pool
gcloud iam workload-identity-pools create "$WIF_POOL_ID" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create provider
gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_ID" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$WIF_POOL_ID" \
  --display-name="GitHub Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
  --attribute-condition="attribute.repository=='${GH_ORG}/${GH_REPO}'"
```

Get the provider resource name (for GitHub secret):

```bash
gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_ID" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$WIF_POOL_ID" \
  --format="value(name)"
```

---

## 3) Create deployer service account + allow GitHub impersonation

```bash
# Create service account
gcloud iam service-accounts create "$DEPLOYER_SA_NAME" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --display-name="GitHub AWX Deployer"

# Allow repo principal set to impersonate SA
gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA_EMAIL" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GH_ORG}/${GH_REPO}"
```

---

## 4) Grant deploy permissions

### 4a) Bootstrap project permissions

```bash
gcloud projects add-iam-policy-binding "$BOOTSTRAP_PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding "$BOOTSTRAP_PROJECT_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

### 4b) Allow project creation + billing association

If using **organization**:

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/resourcemanager.projectCreator"

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/billing.user"
```

If using **folder**:

```bash
gcloud resource-manager folders add-iam-policy-binding "$FOLDER_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/resourcemanager.projectCreator"

gcloud resource-manager folders add-iam-policy-binding "$FOLDER_ID" \
  --member="serviceAccount:${DEPLOYER_SA_EMAIL}" \
  --role="roles/billing.user"
```

> Depending on org policy, `roles/billing.user` may need to be granted on the billing account by a billing admin.

---

## 5) Create remote state bucket

```bash
gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
  --project="$BOOTSTRAP_PROJECT_ID" \
  --location="us-central1" \
  --uniform-bucket-level-access
```

Enable versioning (recommended):

```bash
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning
```

---

## 6) Add GitHub repository secrets

Set these in: **Repo → Settings → Secrets and variables → Actions**

- `GCP_WORKLOAD_IDENTITY_PROVIDER` = provider full resource name from step 2
- `GCP_SERVICE_ACCOUNT` = `${DEPLOYER_SA_EMAIL}`
- `TF_VAR_bootstrap_project_id` = `${BOOTSTRAP_PROJECT_ID}`
- `TF_VAR_billing_account` = `${BILLING_ACCOUNT}`
- `TF_VAR_org_id` = `${ORG_ID}` (or empty if using folder)
- `TF_VAR_folder_id` = `${FOLDER_ID}` (or empty if using org)
- `TF_STATE_BUCKET` = `${TF_STATE_BUCKET}` (bucket name only, no `gs://`)

---

## 7) Validate workflows

1. Run **OpenTofu Infrastructure** with `apply=false`
2. Run **OpenTofu Infrastructure** with `apply=true`
3. Run **Deploy AWX via Ansible** with `awx_hostname=awx.yourdomain.com`

---

## Why these inputs are needed

- `billing_account` + (`org_id` or `folder_id`): required by `google_project` creation.
- `bootstrap_project_id`: provider/auth context and shared location for WIF + state.
- `GCP_WORKLOAD_IDENTITY_PROVIDER` + `GCP_SERVICE_ACCOUNT`: enables GitHub OIDC keyless auth for workflows.
