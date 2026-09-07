# AWS VPC Build

A hand-built, then Terraform-codified, multi-AZ AWS VPC: public/private subnet
isolation, NAT gateway egress, least-privilege security groups, and EC2 access
via SSM Session Manager (no open SSH ports). Built in phases; see
[docs/build-log.md](docs/build-log.md) for the full log of decisions and
troubleshooting.

## Status

- [x] Phase 0 — Guardrails & IAM
- [ ] Phase 1 — CIDR & subnet planning
- [ ] Phase 2 — VPC, subnets, IGW, route tables
- [ ] Phase 3 — NAT gateway
- [ ] Phase 4 — Security groups & NACLs
- [ ] Phase 5 — EC2 deployment
- [ ] Phase 6 — Validation & testing
- [ ] Phase 7 — Documentation
- [ ] Phase 8 — Terraform
- [ ] Phase 9 — Extensions (peering / VPN / endpoints)

## Docs

- [Build log & decisions](docs/build-log.md)
- [CIDR plan](docs/cidr-plan.md)
- [Security groups & NACLs](docs/security-groups.md)
