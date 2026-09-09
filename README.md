# AWS VPC Build

A hand-built, then Terraform-codified, multi-AZ AWS VPC: public/private subnet
isolation, NAT gateway egress, least-privilege security groups, and EC2 access
via SSM Session Manager (no open SSH ports). Built in phases; see
[docs/build-log.md](docs/build-log.md) for the full log of decisions and
troubleshooting.

## Status

- [x] Phase 0 — Guardrails & IAM
- [x] Phase 1 — CIDR & subnet planning
- [x] Phase 2 — VPC, subnets, IGW, route tables
- [x] Phase 3 — NAT gateway
- [x] Phase 4 — Security groups & NACLs
- [x] Phase 5 — EC2 deployment
- [x] Phase 6 — Validation & testing
- [ ] Phase 7 — Documentation
- [ ] Phase 8 — Terraform
- [ ] Phase 9 — Extensions (peering / VPN / endpoints)

## Docs

- [Build log & decisions](docs/build-log.md)
- [CIDR plan](docs/cidr-plan.md)
- [Security groups & NACLs](docs/security-groups.md)
