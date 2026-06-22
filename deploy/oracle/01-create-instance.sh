#!/usr/bin/env bash
#
# Create an Oracle Cloud Always-Free instance and open ports 80/443 on the
# subnet's security list. Requires the OCI CLI (`oci setup config`) and:
#   COMPARTMENT_ID, SUBNET_ID, AVAILABILITY_DOMAIN, IMAGE_ID, SSH_PUBKEY
#
# Defaults to the AMD micro (x86, forever-free). For the ARM A1, set:
#   SHAPE=VM.Standard.A1.Flex  SHAPE_ARGS='--shape-config {"ocpus":1,"memoryInGBs":6}'
set -euo pipefail

: "${COMPARTMENT_ID:?}" "${SUBNET_ID:?}" "${AVAILABILITY_DOMAIN:?}" "${IMAGE_ID:?}" "${SSH_PUBKEY:?}"
SHAPE="${SHAPE:-VM.Standard.E2.1.Micro}"
NAME="${NAME:-arduino-compiler}"

echo "==> Launching ${SHAPE} instance '${NAME}'"
oci compute instance launch \
  --compartment-id "$COMPARTMENT_ID" \
  --availability-domain "$AVAILABILITY_DOMAIN" \
  --shape "$SHAPE" \
  --subnet-id "$SUBNET_ID" \
  --image-id "$IMAGE_ID" \
  --display-name "$NAME" \
  --assign-public-ip true \
  --ssh-authorized-keys-file "$SSH_PUBKEY" \
  --wait-for-state RUNNING

echo "==> Opening TCP 80/443 on the subnet's security list"
SECLIST_ID=$(oci network subnet get --subnet-id "$SUBNET_ID" \
  --query 'data."security-list-ids"[0]' --raw-output)

# Merge two new ingress rules into the existing set (idempotent-ish).
EXISTING=$(oci network security-list get --security-list-id "$SECLIST_ID" \
  --query 'data."ingress-security-rules"' --raw-output)

NEW_RULES='[
  {"protocol":"6","source":"0.0.0.0/0","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":80,"max":80}}},
  {"protocol":"6","source":"0.0.0.0/0","isStateless":false,"tcpOptions":{"destinationPortRange":{"min":443,"max":443}}}
]'

MERGED=$(jq -c -s '.[0] + .[1]' <(echo "$EXISTING") <(echo "$NEW_RULES"))
oci network security-list update --security-list-id "$SECLIST_ID" \
  --ingress-security-rules "$MERGED" --force

echo "==> Done. Public IP:"
oci compute instance list-vnics --instance-id \
  "$(oci compute instance list -c "$COMPARTMENT_ID" --display-name "$NAME" --query 'data[0].id' --raw-output)" \
  --query 'data[0]."public-ip"' --raw-output
