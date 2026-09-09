#!/usr/bin/env bash
# Phase 4b: a custom NACL for the private subnets — explicit deny-in-depth
# on top of the security groups, plus the ephemeral-port rule that NACLs
# require and security groups don't (because NACLs are stateless).
# Run from your terminal with: bash scripts/phase4b-create-nacl.sh
# Requires: network-ids.env in the repo root.

set -euo pipefail

PROFILE="vpc-project"
PROJECT_TAG="aws-vpc-build"

# Resolve paths against the repo root, not the caller's working directory,
# so this works from anywhere: bash scripts/<name>.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDS_FILE="$REPO_ROOT/network-ids.env"

source "$IDS_FILE"

echo "== Creating custom NACL for the private subnets =="
PRIVATE_NACL=$(aws ec2 create-network-acl --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=private-nacl},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'NetworkAcl.NetworkAclId' --output text)
echo "private-nacl created: $PRIVATE_NACL"

echo "== Inbound rules =="
# Rule 90: explicit DENY on SSH, evaluated before anything else. The
# security groups already never allow inbound SSH, so this is deliberately
# redundant — belt-and-suspenders. Even a future SG mistake that opens
# port 22 still can't reach these subnets, because the NACL blocks it
# first regardless of what any SG says.
aws ec2 create-network-acl-entry --network-acl-id "$PRIVATE_NACL" \
  --ingress --rule-number 90 --protocol tcp --rule-action deny \
  --cidr-block 0.0.0.0/0 --port-range From=22,To=22 --profile "$PROFILE"

# Rule 100: allow everything from inside the VPC. One rule covers both the
# bastion reaching app-sg on port 80 AND private instances resolving DNS
# (the VPC's internal resolver lives at 10.0.0.2 — inside this same range),
# instead of enumerating every internal port individually.
aws ec2 create-network-acl-entry --network-acl-id "$PRIVATE_NACL" \
  --ingress --rule-number 100 --protocol -1 --rule-action allow \
  --cidr-block 10.0.0.0/16 --profile "$PROFILE"

# Rule 110: the rule NACLs need that security groups don't, precisely
# because NACLs are stateless. When a private instance makes an outbound
# request (to SSM, or a package repo, via the NAT gateway), the reply comes
# back addressed to whatever random high port the OS picked for that
# connection. Without this rule, that reply is silently dropped and the
# connection just times out — even though the SG and route table both look
# completely fine, which is exactly what makes this bug hard to find live.
aws ec2 create-network-acl-entry --network-acl-id "$PRIVATE_NACL" \
  --ingress --rule-number 110 --protocol tcp --rule-action allow \
  --cidr-block 0.0.0.0/0 --port-range From=1024,To=65535 --profile "$PROFILE"

echo "== Outbound rules =="
aws ec2 create-network-acl-entry --network-acl-id "$PRIVATE_NACL" \
  --egress --rule-number 100 --protocol -1 --rule-action allow \
  --cidr-block 10.0.0.0/16 --profile "$PROFILE"

aws ec2 create-network-acl-entry --network-acl-id "$PRIVATE_NACL" \
  --egress --rule-number 110 --protocol tcp --rule-action allow \
  --cidr-block 0.0.0.0/0 --port-range From=80,To=80 --profile "$PROFILE"

aws ec2 create-network-acl-entry --network-acl-id "$PRIVATE_NACL" \
  --egress --rule-number 120 --protocol tcp --rule-action allow \
  --cidr-block 0.0.0.0/0 --port-range From=443,To=443 --profile "$PROFILE"

echo "== Associating private-nacl with both private subnets =="
# Every subnet starts associated with the VPC's default (allow-all) NACL.
# There's no separate "attach" call — you look up the existing association
# ID and replace it with yours.
PRIVATE_A_ASSOC=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$PRIVATE_A" --profile "$PROFILE" \
  --query "NetworkAcls[0].Associations[?SubnetId=='$PRIVATE_A'].NetworkAclAssociationId" --output text)
PRIVATE_B_ASSOC=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$PRIVATE_B" --profile "$PROFILE" \
  --query "NetworkAcls[0].Associations[?SubnetId=='$PRIVATE_B'].NetworkAclAssociationId" --output text)

aws ec2 replace-network-acl-association --association-id "$PRIVATE_A_ASSOC" \
  --network-acl-id "$PRIVATE_NACL" --profile "$PROFILE" > /dev/null
aws ec2 replace-network-acl-association --association-id "$PRIVATE_B_ASSOC" \
  --network-acl-id "$PRIVATE_NACL" --profile "$PROFILE" > /dev/null
echo "private-a and private-b now use private-nacl instead of the default"

{
  echo ""
  echo "PRIVATE_NACL=$PRIVATE_NACL"
} >> "$IDS_FILE"
echo ""
echo "== Done. network-ids.env updated with PRIVATE_NACL. =="
