#!/usr/bin/env bash
# Teardown for aws-vpc-build.
#
# Default: deletes only what bills — instances, flow log, NAT gateway,
# Elastic IP — and leaves the network layer standing. The VPC, subnets,
# IGW, route tables, security groups and NACL cost nothing to keep, and
# Phase 8 needs them: they are what Terraform gets written against and what
# `terraform plan` output is compared to. Destroying them by default would
# throw away the reference before it has been used.
#
# Run from anywhere:  bash scripts/teardown.sh
#
#   --stop   Stop instances instead of terminating them. Keeps their EBS
#            volumes (~$1.28/month for the pair) so they can be started
#            again without a rebuild.
#   --all    Also delete the network layer and the VPC itself. Use this when
#            you are finished with the project, not between sessions.
#   --yes    Skip the confirmation prompt.

set -uo pipefail
# Deliberately NOT -e, unlike every build script in this project. A teardown
# that stops at the first error can leave a MORE expensive partial state
# than one that presses on — halting right after the instances terminate but
# before the NAT gateway is deleted is the single costliest place to stop.
# Every step here is safe to attempt even if an earlier one failed or the
# resource was already removed by hand.

PROFILE="vpc-project"
REGION="us-east-1"

# Resolve against the repo root, not the caller's working directory, so this
# works from anywhere — same convention as the phase scripts.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDS_FILE="$REPO_ROOT/network-ids.env"
source "$IDS_FILE"

# A previous run comments out the IDs it tore down, so on a re-run those
# variables are simply absent. Default every one to empty rather than
# letting `set -u` abort, then skip any step whose resource is already gone.
# Re-running after a partial teardown has to be safe — that is the whole
# reason this script presses on through errors instead of using `set -e`.
for K in VPC_ID PUBLIC_A PUBLIC_B PRIVATE_A PRIVATE_B IGW_ID PUBLIC_RT PRIVATE_RT \
         NAT_ID EIP_ALLOC_ID PRIVATE_NACL BASTION_SG APP_SG FLOW_LOG_ID; do
  eval ": \${$K:=}"
done

INSTANCE_ACTION="terminate"
NUKE_NETWORK="no"
ASSUME_YES="no"
for arg in "$@"; do
  case "$arg" in
    --stop) INSTANCE_ACTION="stop" ;;
    --all)  NUKE_NETWORK="yes" ;;
    --yes)  ASSUME_YES="yes" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

aws_() { aws "$@" --profile "$PROFILE" --region "$REGION"; }

STAMP="$(date -u +%Y-%m-%d)"

# Comment out an ID that no longer refers to anything, rather than deleting
# the line. A stale ID that still looks live is what troubleshooting entries
# #21 and #23 in the build log are both about.
mark_stale() {
  local key="$1"
  grep -q "^${key}=" "$IDS_FILE" 2>/dev/null || return 0
  sed -i.bak "s|^${key}=|# STALE as of ${STAMP} — ${key}=|" "$IDS_FILE" && rm -f "${IDS_FILE}.bak"
}

# --- Confirmation -----------------------------------------------------------
echo "Profile: $PROFILE   Region: $REGION"
if [ "$NUKE_NETWORK" = "yes" ]; then
  echo "MODE: --all — instances, NAT, EIP, flow log, AND the VPC with everything in it."
  echo "      The Phase 8 Terraform reference goes with it."
else
  echo "MODE: default — instances, NAT, EIP and flow log only."
  echo "      VPC, subnets, IGW, route tables, security groups and NACL are kept."
fi
[ "$INSTANCE_ACTION" = "terminate" ] && ACTION_LABEL="terminated" || ACTION_LABEL="stopped"
echo "Instances will be: $ACTION_LABEL"
if [ "$ASSUME_YES" != "yes" ]; then
  read -r -p "Type 'yes' to continue: " CONFIRM
  [ "$CONFIRM" = "yes" ] || { echo "Aborted — nothing changed."; exit 1; }
fi

# --- Inventory snapshot -----------------------------------------------------
# Captured before anything is destroyed. With --all this is the only record
# of what the network looked like; Phase 8 writes Terraform against it and
# can use the IDs for `terraform import`. Account IDs are stripped, per the
# project's standing rule that they stay out of git.
SNAPSHOT="$REPO_ROOT/docs/network-inventory.json"
echo "== Snapshotting network inventory =="
{
  echo '{'
  echo '  "captured_utc": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
  echo '  "vpc":'            "$(aws_ ec2 describe-vpcs             --vpc-ids "$VPC_ID"                          --output json 2>/dev/null || echo null)"','
  echo '  "subnets":'        "$(aws_ ec2 describe-subnets          --filters "Name=vpc-id,Values=$VPC_ID"       --output json 2>/dev/null || echo null)"','
  echo '  "route_tables":'   "$(aws_ ec2 describe-route-tables     --filters "Name=vpc-id,Values=$VPC_ID"       --output json 2>/dev/null || echo null)"','
  echo '  "internet_gateways":' "$(aws_ ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --output json 2>/dev/null || echo null)"','
  echo '  "security_groups":' "$(aws_ ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID"       --output json 2>/dev/null || echo null)"','
  echo '  "network_acls":'   "$(aws_ ec2 describe-network-acls     --filters "Name=vpc-id,Values=$VPC_ID"       --output json 2>/dev/null || echo null)"
  echo '}'
} | sed -E 's/[0-9]{12}/REDACTED-ACCOUNT-ID/g' > "$SNAPSHOT"
echo "Wrote docs/network-inventory.json"

# --- 1. Instances -----------------------------------------------------------
# Re-queried by tag rather than read from network-ids.env. The file goes
# stale the moment an instance is replaced, and a stale ID here fails
# quietly under `set +e` while the real instances keep billing — the exact
# shape of troubleshooting #23.
echo "== Finding instances tagged Project=aws-vpc-build =="
IDS=$(aws_ ec2 describe-instances \
  --filters "Name=tag:Project,Values=aws-vpc-build" \
            "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -n "$IDS" ]; then
  echo "Found: $IDS"
  if [ "$INSTANCE_ACTION" = "terminate" ]; then
    aws_ ec2 terminate-instances --instance-ids $IDS >/dev/null
    echo "Terminating; waiting for shutdown..."
    aws_ ec2 wait instance-terminated --instance-ids $IDS && echo "Instances terminated."
    mark_stale BASTION_ID; mark_stale APP_ID
  else
    aws_ ec2 stop-instances --instance-ids $IDS >/dev/null
    echo "Stopping; waiting..."
    aws_ ec2 wait instance-stopped --instance-ids $IDS && echo "Instances stopped."
  fi
else
  echo "No live instances found — skipping."
fi

# --- 2. Flow log ------------------------------------------------------------
# Before the NAT, so nothing keeps writing while the rest comes down.
if [ -n "${FLOW_LOG_ID:-}" ]; then
  echo "== Deleting flow log $FLOW_LOG_ID =="
  aws_ ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_ID" >/dev/null && mark_stale FLOW_LOG_ID
fi

# --- 3. NAT gateway ---------------------------------------------------------
# Billing stops at state 'deleted', not at the delete call, and the Elastic
# IP cannot be released until the NAT actually lets go of it. This wait is
# required, not tidiness.
if [ -n "$NAT_ID" ]; then
  echo "== Deleting NAT gateway $NAT_ID (usually 1-3 minutes) =="
  aws_ ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null
  aws_ ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"
  echo "NAT gateway deleted — the largest charge has stopped."
  mark_stale NAT_ID
else
  echo "== No NAT gateway recorded — skipping =="
fi

# --- 4. Elastic IP ----------------------------------------------------------
# An unassociated EIP still bills at ~$0.005/hr, so releasing it matters
# even though the NAT is gone.
if [ -n "$EIP_ALLOC_ID" ]; then
  echo "== Releasing Elastic IP $EIP_ALLOC_ID =="
  aws_ ec2 release-address --allocation-id "$EIP_ALLOC_ID" && mark_stale EIP_ALLOC_ID && echo "Released."
else
  echo "== No Elastic IP recorded — skipping =="
fi

if [ "$NUKE_NETWORK" != "yes" ]; then
  cat <<DONE

== Done. Everything that bills is gone. ==

Kept, at no cost, and needed for Phase 8:
  VPC, subnets, IGW, route tables, security groups, NACL
  CloudWatch log group /aws-vpc-build/flow-logs
  IAM user, roles and policies, and the AWS Budget

The private subnets now hold a route to a deleted NAT gateway. Recreate it
with scripts/phase3-create-nat.sh, which allocates a FRESH Elastic IP — a
different address than the one cited in the Phase 6 logs.

Torn-down IDs are commented out in network-ids.env; the network IDs there
are still live and are the import map for Phase 8.
DONE
  exit 0
fi

# --- 5. Network layer (--all only) ------------------------------------------
# Strict dependency order. Subnets go BEFORE route tables: a route table
# with subnet associations still attached refuses to delete, and deleting a
# subnet clears its association automatically.
echo "== --all: deleting the network layer =="

# A custom NACL can't be deleted while subnets are associated with it — they
# have to go back to the VPC's own default NACL first.
echo "== Reverting private subnets to the default NACL =="
DEFAULT_NACL=$(aws_ ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
  --query 'NetworkAcls[0].NetworkAclId' --output text)
for SUBNET in "$PRIVATE_A" "$PRIVATE_B"; do
  ASSOC=$(aws_ ec2 describe-network-acls \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query "NetworkAcls[0].Associations[?SubnetId=='$SUBNET'].NetworkAclAssociationId" \
    --output text)
  [ -n "$ASSOC" ] && [ "$ASSOC" != "None" ] && \
    aws_ ec2 replace-network-acl-association --association-id "$ASSOC" --network-acl-id "$DEFAULT_NACL" >/dev/null
done
aws_ ec2 delete-network-acl --network-acl-id "$PRIVATE_NACL" && mark_stale PRIVATE_NACL
echo "private-nacl deleted."

# app-sg first: its rule references bastion-sg, not the reverse, so this
# order avoids a DependencyViolation.
echo "== Deleting security groups =="
aws_ ec2 delete-security-group --group-id "$APP_SG"     && mark_stale APP_SG
aws_ ec2 delete-security-group --group-id "$BASTION_SG" && mark_stale BASTION_SG

echo "== Deleting subnets =="
for SUBNET in "$PUBLIC_A" "$PUBLIC_B" "$PRIVATE_A" "$PRIVATE_B"; do
  aws_ ec2 delete-subnet --subnet-id "$SUBNET"
done
for KEY in PUBLIC_A PUBLIC_B PRIVATE_A PRIVATE_B; do mark_stale "$KEY"; done

echo "== Deleting route tables =="
aws_ ec2 delete-route-table --route-table-id "$PUBLIC_RT"  && mark_stale PUBLIC_RT
aws_ ec2 delete-route-table --route-table-id "$PRIVATE_RT" && mark_stale PRIVATE_RT

echo "== Detaching and deleting Internet Gateway =="
aws_ ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws_ ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" && mark_stale IGW_ID

echo "== Deleting VPC =="
if aws_ ec2 delete-vpc --vpc-id "$VPC_ID"; then
  mark_stale VPC_ID
  echo "VPC deleted."
else
  echo "VPC delete failed — something still depends on it. Check for leftover"
  echo "ENIs or security groups, then re-run. Nothing above is billing."
fi

cat <<DONE

== Full teardown complete. ==

Kept: IAM user, roles and policies; CloudWatch log group
/aws-vpc-build/flow-logs; the AWS Budget.

Every torn-down ID is commented out in network-ids.env. The network as it
stood is preserved in docs/network-inventory.json — that snapshot is now
the only record of it, and the reference Phase 8 builds Terraform from.
DONE
