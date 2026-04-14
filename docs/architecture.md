# Architecture

## Infrastructure

- Regional GKE Standard cluster in `us-central1`
- Private nodes in dedicated VPC/subnet
- Cloud NAT for node egress
- Cloud SQL PostgreSQL with private service networking
- Secret Manager for generated credentials
- Global static IP for GKE Ingress

## Deployment flow

1. OpenTofu creates project, APIs, network, GKE, Cloud SQL, secrets.
2. GitHub Actions Ansible job retrieves outputs + secrets.
3. Ansible deploys AWX Operator and AWX CR.
4. Ansible creates ManagedCertificate + Ingress to publish AWX over HTTPS.

## Security notes

- Use GitHub OIDC (no static GCP keys)
- Private GKE nodes
- Cloud SQL private IP only (`ipv4_enabled=false`)
- Secrets stored in Secret Manager, not in Git
