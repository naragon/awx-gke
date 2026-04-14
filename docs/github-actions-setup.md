# GitHub Actions OIDC setup (GCP)

Use Workload Identity Federation (recommended).

## Minimum roles for deployer service account

At org/folder/bootstrap scope (for project creation):
- `roles/resourcemanager.projectCreator`
- `roles/billing.user`

On target project (`sandragon-awx`) after creation:
- `roles/owner` (simple bootstrap option), or granular roles including:
  - `roles/container.admin`
  - `roles/compute.admin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/iam.serviceAccountUser`
  - `roles/cloudsql.admin`
  - `roles/secretmanager.admin`
  - `roles/serviceusage.serviceUsageAdmin`
  - `roles/resourcemanager.projectIamAdmin`

For runtime AWX deploy workflow:
- `roles/container.clusterViewer` + `roles/container.developer` (or admin)
- `roles/secretmanager.secretAccessor`

> Start with broad roles for first bootstrap, then tighten with least privilege.
