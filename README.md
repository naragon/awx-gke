# AWX on GKE (OpenTofu + Ansible)

This repository provisions and deploys:

- **GCP project**: `sandragon-awx`
- **Network**: dedicated VPC/subnets, private GKE nodes, Cloud NAT
- **GKE**: Standard regional cluster (`us-central1`), node pool `e2-standard-4` (autoscaling 1-3)
- **Database**: Cloud SQL PostgreSQL (private IP)
- **Secrets**: Google Secret Manager for DB and AWX admin passwords
- **AWX**: installed via Ansible + AWX Operator, exposed by GKE Ingress + managed TLS
- **CI/CD**: GitHub Actions for OpenTofu and Ansible

## Repository layout

- `tofu/` — OpenTofu infrastructure code
- `ansible/` — AWX installation playbooks/templates
- `.github/workflows/` — CI/CD workflows
- `docs/` — architecture and operations notes

## Prerequisites

1. A **bootstrap GCP project** where your GitHub OIDC service account exists.
2. Billing/org details for project creation:
   - `billing_account`
   - one of `org_id` or `folder_id`
3. GitHub OIDC configured with:
   - Workload Identity Provider
   - Deployer service account
4. A pre-created GCS bucket for OpenTofu state (recommended).

## Required GitHub secrets/variables

Set these in your repository settings:

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `TF_VAR_bootstrap_project_id`
- `TF_VAR_billing_account`
- `TF_VAR_org_id` **or** `TF_VAR_folder_id`
- `TF_STATE_BUCKET` (recommended for shared remote state)

Optional overrides:

- `TF_VAR_project_id` (defaults to `sandragon-awx`)
- `TF_VAR_region` (defaults to `us-central1`)

## Usage

### 1) Provision infrastructure

Run workflow: **OpenTofu Infrastructure** (workflow_dispatch, apply=true).

Or locally:

```bash
cd tofu
cp terraform.tfvars.example terraform.tfvars
# fill required values

tofu init
tofu plan
tofu apply
```

### 2) Deploy AWX

Run workflow: **Deploy AWX via Ansible** and pass `awx_hostname` (e.g. `awx.example.com`).

This workflow will:
- pull infra outputs from OpenTofu state
- fetch generated secrets from Secret Manager
- get GKE credentials
- deploy AWX operator + AWX instance + HTTPS ingress

## Notes

- You said you'll add domain later; for now use any placeholder hostname and update DNS when ready.
- Reserve/point DNS A record to the OpenTofu output `ingress_ip_address`.
- AWX is configured to use **external Cloud SQL PostgreSQL via private IP**.

## Documentation sources used

- Context7: Terraform Google provider/OpenTofu references
- Tavily: AWX external PostgreSQL compatibility and operator docs pointers
