# Security Groups & NACLs

## Security Groups

| Name | Attached to | Direction | Protocol | Port | Source / Destination | Purpose |
|---|---|---|---|---|---|---|
| `bastion-sg` | bastion (public-a) | Inbound | — | — | — | **No inbound rules at all.** SSM Session Manager needs nothing open — management traffic is entirely outbound from the instance. |
| `bastion-sg` | bastion (public-a) | Outbound | All | All | `0.0.0.0/0` | Default allow-all — reaches SSM endpoints and the app tier. |
| `app-sg` | app (private-a) | Inbound | TCP | 80 | `bastion-sg` (security-group reference, not a CIDR) | Only the bastion may reach the app tier's web server. |
| `app-sg` | app (private-a) | Outbound | All | All | `0.0.0.0/0` | Default allow-all — reaches SSM and package repos via NAT. |

**Key detail:** `app-sg`'s inbound rule names `bastion-sg` directly as its source. Confirmed in `describe-security-groups` output as a `UserIdGroupPairs` entry, not an `IpRanges`/`CidrIp` block — the rule stays correct even if subnets are renumbered later.

## Network ACL — `private-nacl`

Applied to: `private-a`, `private-b` (replacing the VPC's default, allow-all NACL association)

### Inbound

| Rule # | Action | Protocol | Port | Source | Purpose |
|---|---|---|---|---|---|
| 90 | DENY | TCP | 22 | `0.0.0.0/0` | Defense-in-depth — blocks SSH even if a future security-group mistake allows it |
| 100 | ALLOW | All | All | `10.0.0.0/16` | VPC-internal traffic (bastion→app, DNS resolution via the VPC's `.2` resolver) |
| 110 | ALLOW | TCP | 1024–65535 | `0.0.0.0/0` | Ephemeral return traffic for connections the instance itself initiated outbound |
| * | DENY | All | All | `0.0.0.0/0` | AWS's implicit final rule — confirmed visible in `describe-network-acls` output as rule `32767` |

### Outbound

| Rule # | Action | Protocol | Port | Destination | Purpose |
|---|---|---|---|---|---|
| 100 | ALLOW | All | All | `10.0.0.0/16` | VPC-internal traffic |
| 110 | ALLOW | TCP | 80 | `0.0.0.0/0` | Outbound HTTP (package repositories) |
| 120 | ALLOW | TCP | 443 | `0.0.0.0/0` | Outbound HTTPS (SSM, package repositories) |
| * | DENY | All | All | `0.0.0.0/0` | AWS's implicit final rule |

## Verified in practice, not just designed (Phase 6)

- `describe-security-groups` confirmed the SG-reference pattern above working exactly as intended.
- An external `nc -zv -G 3 <bastion-public-ip> 22` **timed out**, not refused — the silent-drop behavior a zero-inbound-rule security group is supposed to produce, confirmed from outside the VPC entirely.
- VPC Flow Logs captured 5 real `REJECT` entries on port 22 from **4 distinct external IP addresses** within the first hour of the bastion's existence — unsolicited internet scan traffic, silently dropped. Full detail and screenshot in `docs/build-log.md`, Phase 6.
