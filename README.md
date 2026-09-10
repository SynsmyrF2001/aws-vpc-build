# aws-vpc-build

A hand-built, then Terraform-codified (Phase 8+), multi-AZ AWS VPC: public/private
subnet isolation, NAT gateway egress, least-privilege security groups and a custom
NACL, and EC2 access exclusively through AWS Systems Manager Session Manager —
no SSH keys, no open inbound ports, anywhere in the design.

See `docs/network-diagram.svg` for the as-built architecture diagram.

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

Run `bash scripts/teardown.sh` between sessions to drop this to $0 while
keeping the network intact — see below.

## Repo structure

```
aws-vpc-build/
├── README.md
├── network-ids.env          # Live resource ID inventory — not a secret, tracked on purpose
├── docs/
│   ├── build-log.md         # Every phase, every decision, every mistake and fix
│   ├── cidr-plan.md
│   ├── security-groups.md
│   ├── network-diagram.svg
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

Runs from anywhere — paths resolve against the repo root.

By default it deletes only what bills: instances, flow log, NAT gateway,
Elastic IP. The network layer is left standing on purpose. Subnets, route
tables, the IGW, security groups and the NACL cost nothing to keep, and
Phase 8 needs them — they are what Terraform gets written against and what
`terraform plan` is diffed for. Destroying them by default would throw away
the reference before it has been used.

| Flag | Effect |
|---|---|
| *(none)* | Instances terminated, NAT + EIP + flow log deleted, network kept |
| `--stop` | Stops instances instead of terminating (keeps EBS, ~$1.28/mo) |
| `--all` | Also deletes the network layer and the VPC itself |
| `--yes` | Skips the confirmation prompt |

Details that matter, and why:

- **It waits for the NAT gateway to reach `deleted`** before releasing the
  Elastic IP. Billing stops at that state rather than at the delete call,
  and the address cannot be released until the NAT lets go of it.
- **Instances are re-queried by tag**, never read from `network-ids.env`.
  A stale ID there would fail quietly and leave the real instances billing
  — the failure shape of troubleshooting entries #21 and #23.
- **No `set -e`**, unlike every build script here. A teardown that halts on
  the first error can strand a *more* expensive partial state than one that
  presses on; stopping between instance termination and NAT deletion is the
  costliest place it could stop. Re-running after a partial teardown is
  safe.
- **Under `--all`, subnets are deleted before route tables.** A route table
  still holding subnet associations refuses to delete, and deleting a
  subnet clears its association automatically.
- **A scrubbed inventory snapshot** is written to
  `docs/network-inventory.json` before anything is destroyed — the VPC,
  subnets, route tables, IGW, security groups and NACL as they actually
  stood. Under `--all` that snapshot becomes the only record of the network,
  and it is what Phase 8 writes Terraform from.

Torn-down IDs are commented out in `network-ids.env` rather than deleted, so
the file never claims a resource that is gone. After a default teardown the
network IDs in it are still live, and are the import map for Phase 8.

Left standing in every mode: the IAM user, roles and policies, the
CloudWatch log group `/aws-vpc-build/flow-logs`, and the AWS Budget.

Rebuilding re-runs the phase scripts, and `phase3-create-nat.sh` allocates a
**fresh** Elastic IP — a different address than the one cited in the Phase 6
logs.

## Docs

- [Build log & every architecture decision](docs/build-log.md)
- [CIDR plan](docs/cidr-plan.md)
- [Security groups & NACL rules](docs/security-groups.md)
