#!/usr/bin/env bash
# Phase 3: allocate an Elastic IP, create a NAT gateway in public-a, and
# route both private subnets' outbound traffic through it.
# Run from your terminal with: bash scripts/phase3-create-nat.sh
# Requires: network-ids.env (from Phase 2) in the repo root.

set -euo pipefail

PROFILE="vpc-project"
PROJECT_TAG="aws-vpc-build"

# Pull in VPC_ID, PUBLIC_A, PRIVATE_RT, etc. from Phase 2's output.
# Resolve paths against the repo root, not the caller's working directory,
# so this works from anywhere: bash scripts/<name>.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDS_FILE="$REPO_ROOT/network-ids.env"

source "$IDS_FILE"

echo "== Allocating Elastic IP =="
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=vpc-project-nat-eip},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'AllocationId' --output text)
echo "Elastic IP allocated: $EIP_ALLOC_ID"

echo "== Creating NAT Gateway in public-a =="
# Deliberately ONE NAT gateway, not one per AZ. Two would give true multi-AZ
# egress resilience (private-b wouldn't go dark if public-a's AZ has an
# issue), but at 2x the hourly cost. Documented trade-off, not an oversight —
# see the "single NAT" decision entry in docs/build-log.md.
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUBLIC_A" \
  --allocation-id "$EIP_ALLOC_ID" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=vpc-project-nat},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'NatGateway.NatGatewayId' --output text)
echo "NAT Gateway created: $NAT_ID"

echo "== Waiting for NAT Gateway to become available (usually 1-4 minutes) =="
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID" --profile "$PROFILE"
echo "NAT Gateway is available."

echo "== Routing private subnets through the NAT Gateway =="
aws ec2 create-route --route-table-id "$PRIVATE_RT" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" \
  --profile "$PROFILE" > /dev/null
echo "Private route table $PRIVATE_RT: 0.0.0.0/0 -> $NAT_ID"

# Persist the new IDs so Phase 4+ scripts can source this same file.
{
  echo ""
  echo "NAT_ID=$NAT_ID"
  echo "EIP_ALLOC_ID=$EIP_ALLOC_ID"
} >> "$IDS_FILE"
echo ""
echo "== Done. network-ids.env updated with NAT_ID and EIP_ALLOC_ID. =="
