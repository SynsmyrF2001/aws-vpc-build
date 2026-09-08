# CIDR Plan

VPC: `10.0.0.0/16` (us-east-1)

| Subnet | CIDR | AZ | Tier | Usable IPs |
|---|---|---|---|---|
| public-a | `10.0.0.0/24` | us-east-1a | Public | 251 |
| public-b | `10.0.1.0/24` | us-east-1b | Public | 251 |
| private-a | `10.0.10.0/24` | us-east-1a | Private | 251 |
| private-b | `10.0.11.0/24` | us-east-1b | Private | 251 |

Gaps (`10.0.2.0`–`10.0.9.0`, `10.0.12.0` and above) are reserved for future
tiers or a third AZ without renumbering existing subnets.

Note: AWS reserves 5 addresses per subnet (not the usual 2), hence 251
usable rather than 254.
