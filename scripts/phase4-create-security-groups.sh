#!/usr/bin/env bash
# Phase 4: create security groups for the bastion and app tiers.
# Run from your terminal with: bash scripts/phase4-create-security-groups.sh
# Requires: network-ids.env (from Phase 2/3) in the repo root.

set -euo pipefail

PROFILE="vpc-project"
PROJECT_TAG="aws-vpc-build"

# Resolve paths against the repo root, not the caller's working directory,
# so this works from anywhere: bash scripts/<name>.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDS_FILE="$REPO_ROOT/network-ids.env"

source "$IDS_FILE"

echo "== Creating bastion security group =="
BASTION_SG=$(aws ec2 create-security-group \
  --group-name bastion-sg \
  --description "Bastion host - management via SSM only, no inbound rules" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=bastion-sg},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'GroupId' --output text)
echo "bastion-sg created: $BASTION_SG"
# Deliberately zero inbound rules. SSM Session Manager works entirely over
# outbound HTTPS from the instance to AWS's SSM service — nothing needs to
# be open inbound at all. The default "allow all outbound" egress rule is
# left untouched, which is all a bastion needs to reach SSM or to test
# connectivity against the app tier.

echo "== Creating app security group =="
APP_SG=$(aws ec2 create-security-group \
  --group-name app-sg \
  --description "App tier - inbound only from the bastion security group" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=app-sg},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'GroupId' --output text)
echo "app-sg created: $APP_SG"

echo "== Authorizing bastion-sg -> app-sg on tcp/80 =="
# The important detail: the source here is another security group, not a
# CIDR block. Any instance in bastion-sg can reach port 80 on any instance
# in app-sg, regardless of which subnet or IP either one ends up with —
# the rule stays correct even if subnets get renumbered later. Adjust the
# port in Phase 5 if the app ends up listening on something other than 80.
aws ec2 authorize-security-group-ingress \
  --group-id "$APP_SG" \
  --protocol tcp --port 80 \
  --source-group "$BASTION_SG" \
  --profile "$PROFILE" > /dev/null
echo "app-sg now allows inbound tcp/80 from bastion-sg ($BASTION_SG)"

{
  echo ""
  echo "BASTION_SG=$BASTION_SG"
  echo "APP_SG=$APP_SG"
} >> "$IDS_FILE"
echo ""
echo "== Done. network-ids.env updated with BASTION_SG and APP_SG. =="
