# Security Groups & NACLs

Rule tables below are transcribed from `aws ec2 describe-security-groups` and
`describe-network-acls` against the live build, not from the creation scripts
— they are what AWS actually had in place, captured at the end of Phase 6.
Raw output is kept in `phase7-sg-snapshot.json` and `phase7-nacl-snapshot.json`
(account IDs redacted).

Security groups are **stateful**: a permitted inbound flow's response is
allowed back out automatically. NACLs are **stateless**, which is why the
NACL below needs an explicit ephemeral-port rule that the security groups
never require.

## Security groups

### `bastion-sg` — `sg-015f1011f22037bdd`

> Bastion host — management via SSM only, no inbound rules

| Direction | Protocol | Ports | Source / Destination |
|---|---|---|---|
| Inbound | — | — | **none — no inbound rules at all** |
| Outbound | all | all | `0.0.0.0/0` |

The empty inbound set is the whole point of the design, not an omission.
Session Manager works by having the instance's SSM agent open an *outbound*
connection to the SSM service, so administrative access needs no listening
port and no inbound allowance. This is what makes the external
`nc -zv -G 3 <bastion-public-ip> 22` test time out rather than be refused:
with no matching rule, the packet is dropped silently instead of being
answered with a TCP reset.

### `app-sg` — `sg-01bd6bd704541a10a`

> App tier — inbound only from the bastion security group

| Direction | Protocol | Ports | Source / Destination |
|---|---|---|---|
| Inbound | TCP | 80 | `sg-015f1011f22037bdd` (`bastion-sg`) |
| Outbound | all | all | `0.0.0.0/0` |

The inbound source is the bastion's **security group**, not a CIDR. That
distinction matters: the rule keeps working if the bastion is replaced and
comes back with a different private IP, and it cannot be satisfied by some
other host that merely happens to sit in the same subnet range. It is
identity-based rather than address-based.

Outbound is open because the app instance genuinely needs it — reaching the
SSM service endpoints and pulling packages, both via the NAT gateway.

## Network ACL — `acl-0b64faead7bd85f47`

Custom (non-default), associated with both private subnets:
`subnet-042dcdc30d65fb74e` (private-a) and `subnet-0136f816653eccb9b`
(private-b).

### Inbound

| Rule # | Protocol | Ports | Source | Action |
|---|---|---|---|---|
| 90 | TCP | 22 | `0.0.0.0/0` | **DENY** |
| 100 | all | all | `10.0.0.0/16` | ALLOW |
| 110 | TCP | 1024–65535 | `0.0.0.0/0` | ALLOW |
| 32767 | all | all | `0.0.0.0/0` | DENY (implicit) |

### Outbound

| Rule # | Protocol | Ports | Destination | Action |
|---|---|---|---|---|
| 100 | all | all | `10.0.0.0/16` | ALLOW |
| 110 | TCP | 80 | `0.0.0.0/0` | ALLOW |
| 120 | TCP | 443 | `0.0.0.0/0` | ALLOW |
| 32767 | all | all | `0.0.0.0/0` | DENY (implicit) |

### Why the rules are numbered the way they are

NACL rules evaluate in ascending order and stop at the first match, so
ordering is the design, not a formality.

**Rule 90 sits before rule 100 deliberately.** Rule 100 allows all traffic
from `10.0.0.0/16`, which would include SSH from inside the VPC. Putting the
SSH deny at 90 means it is evaluated first and wins. This is the
defense-in-depth layer: even if a security group were later misconfigured to
permit port 22, the NACL still refuses it for the private subnets. Placing
the same deny at, say, 110 would make it dead code.

**Rule 110 inbound exists because NACLs are stateless.** When the app
instance makes an outbound request through the NAT gateway, the reply
arrives on an ephemeral high port. A security group would allow that return
traffic automatically; a NACL will not, so the ephemeral range has to be
opened explicitly or every outbound request would hang. It is scoped to
1024–65535 rather than `all` so it grants only what return traffic actually
needs.

**Outbound is restricted to 80 and 443 plus VPC-internal.** That covers
package installs and the SSM agent's HTTPS calls without granting general
egress on arbitrary ports.

## Verification

Both tiers were confirmed working in Phase 6 rather than assumed — see
`build-log.md`:

- `curl http://10.0.10.81` from the bastion returned the app's nginx page,
  exercising `app-sg` rule 1 and NACL rules 100 in both directions
- An SSM session opened directly into the app instance, proving its outbound
  path through the NAT and NACL egress rules 110/120
- An external SSH attempt against the bastion timed out rather than being
  refused, confirming `bastion-sg`'s empty inbound set
- VPC Flow Logs recorded five REJECTs on port 22 from four distinct external
  IPs — unsolicited internet scanning, dropped by the same empty inbound set
