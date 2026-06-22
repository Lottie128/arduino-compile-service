#!/usr/bin/env bash
# EC2 user-data (cloud-init): self-provision the compile service on first boot.
# 01-create-instance.sh substitutes __COMPILE_TOKEN__ and __DOMAIN__.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git

cd /opt
git clone https://github.com/Lottie128/arduino-compile-service.git
COMPILE_TOKEN="__COMPILE_TOKEN__" DOMAIN="__DOMAIN__" \
  bash /opt/arduino-compile-service/deploy/common/provision.sh
