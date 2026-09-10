#!/usr/bin/env bash
# Teardown: delete every billing resource, keep the free network scaffolding.
# Run from your terminal with: bash scripts/teardown.sh
# Requires: network-ids.env in the repo root.
#
# Removes, in dependency order: EC2 instances -> flow log -> NAT gateway ->
# Elastic IP -> CloudWatch log group. Leaves the VPC, subnets, IGW, route
# tables, security groups and NACL in place — none of those cost anything,
# and they are the reference Phase 8 (Terraform) codifies against.
#
# Pass --stop to stop the instances instead of terminating them. Stopped
# instances keep their EBS volumes (~$1.28/mo for the pair) and can be
# started again; terminated ones are gone and get rebuilt with
# scripts/phase5-launch-instances.sh.
#
# Pass --all to additionally delete the VPC and everything in it.

set -euo pipefail

PROFILE="vpc-project"
REGION="us-east-1"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDS_FILE="$REPO_ROOT/network-ids.env"
source "$IDS_FILE"

INSTANCE_ACTION="terminate"
NUKE_VPC="no"
for arg in "$@"; do
  case "$arg" in
    --stop) INSTANCE_ACTION="stop" ;;
    --all)  NUKE_VPC="yes" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

aws_() { aws "$@" --profile "$PROFILE" --region "$REGION"; }

echo "== This will $INSTANCE_ACTION instances and delete the NAT gateway =="
[ "$NUKE_VPC" = "yes" ] && echo "== --all given: the VPC itself will also be deleted =="
read -r -p "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 1; }

# --- 1. Instances -----------------------------------------------------------
# Re-query rather than trusting the IDs file: it goes stale the moment an
# instance is replaced, and acting on a wrong instance ID is unrecoverable.
echo "== Finding instances tagged Project=aws-vpc-build =="
IDS=$(aws_ ec2 describe-instances \
  --filters "Name=tag:Project,Values=aws-vpc-build" \
            "Name=instance-state-name,Values=running,stopped,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -n "$IDS" ]; then
  echo "Found: $IDS"
  if [ "$INSTANCE_ACTION" = "terminate" ]; then
    aws_ ec2 terminate-instances --instance-ids $IDS >/dev/null
    echo "Terminating; waiting for shutdown to complete..."
    aws_ ec2 wait instance-terminated --instance-ids $IDS
  else
    aws_ ec2 stop-instances --instance-ids $IDS >/dev/null
    echo "Stopping; waiting..."
    aws_ ec2 wait instance-stopped --instance-ids $IDS
  fi
  echo "Instances ${INSTANCE_ACTION}d."
else
  echo "No live instances found — skipping."
fi

# --- 2. Flow log ------------------------------------------------------------
# Deleted before the NAT so nothing keeps writing while the rest comes down.
if [ -n "${FLOW_LOG_ID:-}" ]; then
  echo "== Deleting flow log $FLOW_LOG_ID =="
  aws_ ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_ID" >/dev/null || true
fi

# --- 3. NAT gateway ---------------------------------------------------------
# Billing stops at 'deleted', not at the delete call. The EIP cannot be
# released until the NAT actually lets go of it, so this wait is required,
# not just tidy.
echo "== Deleting NAT gateway $NAT_ID =="
aws_ ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null || true
echo "Waiting for it to reach 'deleted' (usually 1-3 minutes)..."
aws_ ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID" || true
echo "NAT gateway deleted — the largest charge has stopped."

# --- 4. Elastic IP ----------------------------------------------------------
# An unassociated EIP bills at ~$0.005/hr, so releasing it matters even
# though the NAT is gone.
echo "== Releasing Elastic IP $EIP_ALLOC_ID =="
aws_ ec2 release-address --allocation-id "$EIP_ALLOC_ID" >/dev/null || true
echo "Released."

# --- 5. CloudWatch log group ------------------------------------------------
echo "== Deleting log group /aws-vpc-build/flow-logs =="
aws_ logs delete-log-group --log-group-name "/aws-vpc-build/flow-logs" >/dev/null 2>&1 \
  || echo "  (already gone or never created)"

if [ "$NUKE_VPC" != "yes" ]; then
  cat <<'DONE'

== Done. Billing resources removed. ==

Still in place, at no cost: VPC, subnets, IGW, route tables, security
groups, NACL. The private subnets now have a dangling route to a deleted
NAT gateway — recreate it with scripts/phase3-create-nat.sh, which will
allocate a fresh Elastic IP (a different address than before).

Note NAT_ID and EIP_ALLOC_ID in network-ids.env are now stale.
DONE
  exit 0
fi

# --- 6. Full VPC teardown (--all) -------------------------------------------
# Strict dependency order: AWS refuses each delete until its dependents are
# gone, so this unwinds Phase 2-4 in reverse.
echo "== --all: deleting the VPC and its contents =="

# app-sg references bastion-sg, so it has to go first.
for SG in "$APP_SG" "$BASTION_SG"; do
  echo "Deleting security group $SG"
  aws_ ec2 delete-security-group --group-id "$SG" >/dev/null 2>&1 \
    || echo "  (skipped — still in use or already gone)"
done

for SUBNET in "$PUBLIC_A" "$PUBLIC_B" "$PRIVATE_A" "$PRIVATE_B"; do
  echo "Deleting subnet $SUBNET"
  aws_ ec2 delete-subnet --subnet-id "$SUBNET" >/dev/null 2>&1 || echo "  (skipped)"
done

echo "Deleting NACL $PRIVATE_NACL"
aws_ ec2 delete-network-acl --network-acl-id "$PRIVATE_NACL" >/dev/null 2>&1 || echo "  (skipped)"

for RT in "$PUBLIC_RT" "$PRIVATE_RT"; do
  echo "Deleting route table $RT"
  aws_ ec2 delete-route-table --route-table-id "$RT" >/dev/null 2>&1 || echo "  (skipped)"
done

echo "Detaching and deleting IGW $IGW_ID"
aws_ ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" >/dev/null 2>&1 || true
aws_ ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" >/dev/null 2>&1 || echo "  (skipped)"

echo "Deleting VPC $VPC_ID"
aws_ ec2 delete-vpc --vpc-id "$VPC_ID" >/dev/null 2>&1 || echo "  (skipped — check for leftover dependencies)"

echo
echo "== Full teardown complete. network-ids.env is now entirely stale. =="
