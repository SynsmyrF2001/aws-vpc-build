#!/usr/bin/env bash
# Phase 5: launch the bastion (public) and app (private) EC2 instances.
# Run from your terminal with: bash scripts/phase5-launch-instances.sh
# Requires: network-ids.env in the repo root; app-userdata.sh alongside
# this script.

set -euo pipefail

PROFILE="vpc-project"
REGION="us-east-1"
PROJECT_TAG="aws-vpc-build"
INSTANCE_TYPE="t3.micro"
ROLE_NAME="vpc-project-ec2-ssm-role"

# Resolve paths against this script's own location, not the caller's working
# directory, so this works from anywhere: bash scripts/<name>.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDS_FILE="$SCRIPT_DIR/../network-ids.env"
USERDATA="$SCRIPT_DIR/app-userdata.sh"

source "$IDS_FILE"

echo "== Looking up the latest Amazon Linux 2023 AMI =="
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --profile "$PROFILE" --region "$REGION" \
  --query 'Parameters[0].Value' --output text)
echo "Using AMI: $AMI_ID"

echo "== Checking for the SSM instance profile =="
# The IAM role from Phase 0 and an "instance profile" are two different
# objects that happen to share a name because the IAM console auto-created
# both together at the time. This confirms that actually happened, rather
# than assuming it, and creates the profile manually if it somehow didn't.
if aws iam get-instance-profile --instance-profile-name "$ROLE_NAME" --profile "$PROFILE" &>/dev/null; then
  echo "Instance profile $ROLE_NAME already exists."
else
  echo "Instance profile missing — creating it."
  aws iam create-instance-profile --instance-profile-name "$ROLE_NAME" --profile "$PROFILE"
  aws iam add-role-to-instance-profile --instance-profile-name "$ROLE_NAME" --role-name "$ROLE_NAME" --profile "$PROFILE"
  echo "Waiting for IAM propagation..."
  sleep 15
fi

echo "== Launching bastion in public-a =="
BASTION_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$PUBLIC_A" --security-group-ids "$BASTION_SG" \
  --iam-instance-profile "Name=$ROLE_NAME" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=bastion},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --region "$REGION" \
  --query 'Instances[0].InstanceId' --output text)
echo "bastion launching: $BASTION_ID"

echo "== Launching app instance in private-a =="
APP_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$PRIVATE_A" --security-group-ids "$APP_SG" \
  --iam-instance-profile "Name=$ROLE_NAME" \
  --user-data "file://$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=app},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --region "$REGION" \
  --query 'Instances[0].InstanceId' --output text)
echo "app instance launching: $APP_ID"

echo "== Waiting for both instances to reach running state =="
aws ec2 wait instance-running --instance-ids "$BASTION_ID" "$APP_ID" --profile "$PROFILE" --region "$REGION"
echo "Both instances are running."

{
  echo ""
  echo "BASTION_ID=$BASTION_ID"
  echo "APP_ID=$APP_ID"
} >> "$IDS_FILE"
echo ""
echo "== Done. network-ids.env updated with BASTION_ID and APP_ID. =="
