# aws-vpc-build

A hand-built, then Terraform-codified (Phase 8+), multi-AZ AWS VPC: public/private
subnet isolation, NAT gateway egress, least-privilege security groups and a custom
NACL, and EC2 access exclusively through AWS Systems Manager Session Manager —
no SSH keys, no open inbound ports, anywhere in the design.

See `docs/network-diagram.png` for the as-built architecture diagram.

## What this demonstrates

- VPC network design from first principles: CIDR planning, route tables,
  IGW/NAT routing, defense-in-depth via security groups *and* a NACL
- IAM built iteratively against real permission errors, not granted broadly
  up front — every scoped policy in this project exists because something
  concrete failed without it (see `docs/build-log.md` for the full trail)
- Zero-SSH infrastructure access via SSM Session Manager, including a
  private instance with no public IP at all
- Validated, not just designed: a genuine positive-path test, a genuine
  negative-path test, and VPC Flow Logs as permanent evidence — including
  real, unsolicited internet scan traffic captured and rejected
- An honest build log: every mistake, every wrong assumption, and every fix
  kept in place rather than smoothed over after the fact

## Architecture

- VPC: `10.0.0.0/16`, `us-east-1`
- 2 AZs, 4 subnets (2 public, 2 private) — full plan in `docs/cidr-plan.md`
- 1 NAT Gateway, single-AZ by design — a documented cost trade-off, not an
  oversight (`docs/build-log.md`, decision #11)
- Bastion + app EC2 instances (Amazon Linux 2023), reached only via an IAM
  instance role and SSM — no key pairs exist anywhere in this project
- Security groups + a custom NACL with an explicit deny rule as
  defense-in-depth — full rule tables in `docs/security-groups.md`
- VPC Flow Logs → CloudWatch, queried with Logs Insights

## Status

- [x] Phase 0 — Guardrails & IAM
- [x] Phase 1 — CIDR & subnet planning
- [x] Phase 2 — VPC, subnets, IGW, route tables
- [x] Phase 3 — NAT gateway
- [x] Phase 4 — Security groups & NACL
- [x] Phase 5 — EC2 deployment
- [x] Phase 6 — Validation (positive path, negative path, Flow Logs proof)
- [x] Phase 7 — Documentation (this)
- [ ] Phase 8 — Terraform
- [ ] Phase 9 — Extensions (peering / VPN / endpoints / multi-AZ NAT)

## Cost

This account runs under AWS's credit-based Free Tier (~$100–200 credit,
6-month expiry), so actual out-of-pocket may show $0 — the figures below are
real usage cost, which is what actually draws down the credit.

| Resource | Rate | Cost if left running |
|---|---|---|
| NAT Gateway | ~$0.045/hr + $0.045/GB processed | ~$1.08/day |
| 2× `t3.micro` EC2 | ~$0.0104/hr each | ~$0.50/day combined |
| Public IPv4 × 2 (NAT EIP + bastion) | $0.005/hr per address | ~$0.24/day |
| 2× 8 GB gp3 EBS | ~$0.08/GB-month | ~$0.04/day |
| CloudWatch (Flow Logs) | Ingestion + storage at this volume | Pennies/month |
| **Total while running** | | **~$1.85/day (~$56/mo)** |

Run `bash scripts/teardown.sh` to remove everything that bills when not
actively working — see below.

## Repo structure

```
aws-vpc-build/
├── README.md
├── network-ids.env          # Live resource ID inventory — not a secret, tracked on purpose
├── docs/
│   ├── build-log.md         # Every phase, every decision, every mistake and fix
│   ├── cidr-plan.md
│   ├── security-groups.md
│   ├── network-diagram.png
│   └── screenshots/
├── scripts/
│   ├── phase2-create-network.sh
│   ├── phase3-create-nat.sh
│   ├── phase4-create-security-groups.sh
│   ├── phase4b-create-nacl.sh
│   ├── phase5-launch-instances.sh
│   ├── app-userdata.sh      # Bootstraps nginx on the private app instance
│   └── teardown.sh
├── terraform/               # Phase 8
└── .github/workflows/       # Phase 8
```

## Teardown

```bash
bash scripts/teardown.sh
```

By default this removes everything that bills, in the order AWS's own
dependency rules require — instances, flow log, NAT gateway, Elastic IP,
then the CloudWatch log group. It waits for the NAT gateway to actually
reach `deleted` before releasing the Elastic IP, because billing stops at
that state rather than at the delete call, and the address cannot be
released until the NAT lets go of it.

The free network scaffolding — VPC, subnets, IGW, route tables, security
groups, NACL — is left standing on purpose. None of it costs anything, and
it is the reference Phase 8 codifies Terraform against.

Two flags:

- `--stop` stops the instances instead of terminating them, keeping their
  EBS volumes (~$1.28/month for the pair) so they can be started again
- `--all` additionally deletes the VPC and everything inside it: security
  groups, subnets, NACL, route tables, IGW, then the VPC itself

Left standing either way: the IAM user, roles and policies, and the AWS
Budget — all free, and all needed for a rebuild.

After teardown, `NAT_ID` and `EIP_ALLOC_ID` in `network-ids.env` are stale.
Re-running `scripts/phase3-create-nat.sh` allocates a **fresh** Elastic IP,
which will be a different address than the one cited in the Phase 6 logs.

## Docs

- [Build log & every architecture decision](docs/build-log.md)
- [CIDR plan](docs/cidr-plan.md)
- [Security groups & NACL rules](docs/security-groups.md)
