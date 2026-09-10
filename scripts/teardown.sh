#!/usr/bin/env bash
# Full teardown for aws-vpc-build. Deletes every resource created across
# Phases 2-6, in the order AWS's own dependency rules require.
# Run from your terminal with: bash scripts/teardown.sh (from the repo root,
# so network-ids.env resolves — or adjust the source path below).

set -uo pipefail
# Deliberately NOT -e here, unlike every build script so far. A teardown
# script that stops at the first error can leave a MORE expensive partial
# state than one that presses on — e.g. stopping right after instances
# terminate but before the NAT gateway is deleted is the single costliest
# possible place to halt. Every step here is safe to attempt even if an
# earlier one already failed or the resource was already removed by hand.

PROFILE="vpc-project"
REGION="us-east-1"

source ./network-ids.env

echo "== Terminating EC2 instances =="
aws ec2 terminate-instances --instance-ids "$BASTION_ID" "$APP_ID" --profile "$PROFILE" --region "$REGION"
aws ec2 wait instance-terminated --instance-ids "$BASTION_ID" "$APP_ID" --profile "$PROFILE" --region "$REGION"
echo "Both instances terminated."

echo "== Deleting NAT Gateway (this takes a few minutes) =="
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" --profile "$PROFILE" --region "$REGION"
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID" --profile "$PROFILE" --region "$REGION"
echo "NAT Gateway deleted."

echo "== Releasing Elastic IP =="
aws ec2 release-address --allocation-id "$EIP_ALLOC_ID" --profile "$PROFILE" --region "$REGION"

echo "== Deleting VPC Flow Log =="
aws ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_ID" --profile "$PROFILE" --region "$REGION"

echo "== Reverting private subnets to the VPC's default NACL =="
# A custom NACL can't be deleted while subnets are still associated with it
# — they have to go back to the VPC's own default NACL first.
DEFAULT_NACL=$(aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
  --profile "$PROFILE" --region "$REGION" \
  --query 'NetworkAcls[0].NetworkAclId' --output text)
PRIVATE_A_ASSOC=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$PRIVATE_A" --profile "$PROFILE" --region "$REGION" \
  --query "NetworkAcls[0].Associations[?SubnetId=='$PRIVATE_A'].NetworkAclAssociationId" --output text)
PRIVATE_B_ASSOC=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$PRIVATE_B" --profile "$PROFILE" --region "$REGION" \
  --query "NetworkAcls[0].Associations[?SubnetId=='$PRIVATE_B'].NetworkAclAssociationId" --output text)
aws ec2 replace-network-acl-association --association-id "$PRIVATE_A_ASSOC" --network-acl-id "$DEFAULT_NACL" --profile "$PROFILE" --region "$REGION" > /dev/null
aws ec2 replace-network-acl-association --association-id "$PRIVATE_B_ASSOC" --network-acl-id "$DEFAULT_NACL" --profile "$PROFILE" --region "$REGION" > /dev/null
aws ec2 delete-network-acl --network-acl-id "$PRIVATE_NACL" --profile "$PROFILE" --region "$REGION"
echo "private-nacl deleted."

echo "== Deleting security groups =="
# app-sg first: its rule references bastion-sg, not the reverse, so this
# order avoids a DependencyViolation on the delete call.
aws ec2 delete-security-group --group-id "$APP_SG" --profile "$PROFILE" --region "$REGION"
aws ec2 delete-security-group --group-id "$BASTION_SG" --profile "$PROFILE" --region "$REGION"
echo "Security groups deleted."

echo "== Deleting route tables =="
aws ec2 delete-route-table --route-table-id "$PUBLIC_RT" --profile "$PROFILE" --region "$REGION"
aws ec2 delete-route-table --route-table-id "$PRIVATE_RT" --profile "$PROFILE" --region "$REGION"
echo "Route tables deleted."

echo "== Detaching and deleting Internet Gateway =="
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --profile "$PROFILE" --region "$REGION"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --profile "$PROFILE" --region "$REGION"
echo "Internet Gateway detached and deleted."

echo "== Deleting subnets =="
for SUBNET in "$PUBLIC_A" "$PUBLIC_B" "$PRIVATE_A" "$PRIVATE_B"; do
  aws ec2 delete-subnet --subnet-id "$SUBNET" --profile "$PROFILE" --region "$REGION"
done
echo "All four subnets deleted."

echo "== Deleting VPC =="
aws ec2 delete-vpc --vpc-id "$VPC_ID" --profile "$PROFILE" --region "$REGION"
echo "VPC deleted."

echo ""
echo "== Teardown complete. =="
echo "Deliberately NOT deleted (free or cheap to keep, useful for a rebuild):"
echo "  - IAM user, role, and policies (vpc-project-*)"
echo "  - CloudWatch log group /aws-vpc-build/flow-logs"
echo "  - AWS Budget aws-vpc-build-budget"
