#!/usr/bin/env bash
#
# Create an Azure free-tier B1s VM for the compile service: resource group +
# Ubuntu 22.04 VM + NSG rules for 22/80/443. Requires the Azure CLI (`az login`).
#
# Env: LOCATION, RG (resource group), VM_NAME (default arduino-compiler)
# Optional (enables cloud-init self-provisioning): COMPILE_TOKEN, DOMAIN
set -euo pipefail

LOCATION="${LOCATION:?set LOCATION e.g. centralindia}"
RG="${RG:-arduino-compiler-rg}"
VM_NAME="${VM_NAME:-arduino-compiler}"

echo "==> Resource group ${RG}"
az group create --name "$RG" --location "$LOCATION" -o none

CUSTOM_DATA_ARG=()
if [ -n "${COMPILE_TOKEN:-}" ] && [ -n "${DOMAIN:-}" ]; then
  echo "==> Rendering cloud-init"
  tmp=$(mktemp)
  sed -e "s|__COMPILE_TOKEN__|${COMPILE_TOKEN}|" -e "s|__DOMAIN__|${DOMAIN}|" \
      "$(dirname "$0")/cloud-init.yaml" > "$tmp"
  CUSTOM_DATA_ARG=(--custom-data "$tmp")
fi

echo "==> Creating B1s VM (free-tier eligible)"
az vm create \
  --resource-group "$RG" --name "$VM_NAME" \
  --image Ubuntu2204 --size Standard_B1s \
  --admin-username azureuser --generate-ssh-keys \
  --public-ip-sku Standard "${CUSTOM_DATA_ARG[@]}" \
  -o table

echo "==> Opening 80 and 443 (22 is opened by default)"
az vm open-port --resource-group "$RG" --name "$VM_NAME" --port 80 --priority 1001 -o none
az vm open-port --resource-group "$RG" --name "$VM_NAME" --port 443 --priority 1002 -o none

IP=$(az vm show -d -g "$RG" -n "$VM_NAME" --query publicIps -o tsv)
echo "==> Running. Public IP: $IP"
