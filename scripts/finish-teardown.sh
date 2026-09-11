#!/usr/bin/env bash
# Finishes what the modified teardown.sh (MODE: default) left alive on
# purpose: VPC, subnets, IGW, route tables, security groups, NACL.
# Run from the repo root: bash scripts/finish-teardown.sh

set -uo pipefail  # same reasoning as the original teardown script — press
                  # on past individual failures rather than stopping early

PROFILE="vpc-project"
REGION="us-east-1"

source ./network-ids.env

echo "== Reverting private subnets to the VPC's default NACL =="
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
echo "== Full teardown complete. Nothing billable or non-default remains. =="
