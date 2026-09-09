#!/usr/bin/env bash
# Phase 2: create the VPC, four subnets, IGW, and route tables.
# Run from your terminal with: bash scripts/phase2-create-network.sh
# Requires: AWS CLI v2, the `vpc-project` profile configured in Phase 0.

set -euo pipefail  # stop immediately on any failed command — don't limp
                   # forward with a half-built network and no idea which
                   # step actually failed

PROFILE="vpc-project"
REGION="us-east-1"
PROJECT_TAG="aws-vpc-build"

echo "== Creating VPC =="
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=vpc-project},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --region "$REGION" \
  --query 'Vpc.VpcId' --output text)
echo "VPC created: $VPC_ID"

# Custom VPCs are created with DNS hostnames OFF by default (DNS support is
# on by default, hostnames are not — an easy miss). Without this, EC2
# instances you launch in the public subnets in Phase 5 won't get a
# resolvable public DNS name, and nothing will error to tell you why.
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" \
  --enable-dns-hostnames '{"Value":true}' --profile "$PROFILE"

echo "== Creating subnets =="
PUBLIC_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" \
  --cidr-block 10.0.0.0/24 --availability-zone us-east-1a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=public-a},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'Subnet.SubnetId' --output text)

PUBLIC_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 --availability-zone us-east-1b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=public-b},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'Subnet.SubnetId' --output text)

PRIVATE_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" \
  --cidr-block 10.0.10.0/24 --availability-zone us-east-1a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=private-a},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'Subnet.SubnetId' --output text)

PRIVATE_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" \
  --cidr-block 10.0.11.0/24 --availability-zone us-east-1b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=private-b},{Key=Project,Value=$PROJECT_TAG}]" \
  --profile "$PROFILE" --query 'Subnet.SubnetId' --output text)

echo "public-a:  $PUBLIC_A"
echo "public-b:  $PUBLIC_B"
echo "private-a: $PRIVATE_A"
echo "private-b: $PRIVATE_B"

# Auto-assign public IPs on the two public subnets. This alone does NOT make
# them "public" — that also requires the route table association below.
# A subnet is only genuinely public once both conditions are true together.
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_A" \
  --map-public-ip-on-launch --profile "$PROFILE"
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_B" \
  --map-public-ip-on-launch --profile "$PROFILE"

echo "== Creating and attaching Internet Gateway =="
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=vpc-project-igw}]" \
  --profile "$PROFILE" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" \
  --internet-gateway-id "$IGW_ID" --profile "$PROFILE"
echo "IGW created and attached: $IGW_ID"

echo "== Public route table =="
PUBLIC_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]" \
  --profile "$PROFILE" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUBLIC_RT" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --profile "$PROFILE" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUBLIC_RT" --subnet-id "$PUBLIC_A" --profile "$PROFILE" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUBLIC_RT" --subnet-id "$PUBLIC_B" --profile "$PROFILE" > /dev/null
echo "Public route table: $PUBLIC_RT (0.0.0.0/0 -> $IGW_ID)"

echo "== Private route table =="
# Deliberately NO 0.0.0.0/0 route here yet — that's Phase 3, once the NAT
# gateway exists. Using an explicit route table here (not the VPC's implicit
# "main" table) so it's obvious later exactly which subnets are private and
# why, instead of relying on an unnamed default.
PRIVATE_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=private-rt}]" \
  --profile "$PROFILE" --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --route-table-id "$PRIVATE_RT" --subnet-id "$PRIVATE_A" --profile "$PROFILE" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRIVATE_RT" --subnet-id "$PRIVATE_B" --profile "$PROFILE" > /dev/null
echo "Private route table: $PRIVATE_RT (no internet route — intentional)"

echo ""
echo "== Done. Save these IDs — every later phase references them. =="
cat <<EOF
VPC_ID=$VPC_ID
PUBLIC_A=$PUBLIC_A
PUBLIC_B=$PUBLIC_B
PRIVATE_A=$PRIVATE_A
PRIVATE_B=$PRIVATE_B
IGW_ID=$IGW_ID
PUBLIC_RT=$PUBLIC_RT
PRIVATE_RT=$PRIVATE_RT
EOF
