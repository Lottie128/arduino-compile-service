# Deploy on Oracle Cloud (Always Free)

Oracle's **Always Free** tier is the only one of the three that's free *forever*
— ideal for a permanent compile host.

## Choose the shape
| Shape | Free allowance | Notes |
|---|---|---|
| **VM.Standard.A1.Flex** (ARM) | up to **4 OCPU / 24 GB**, forever | Best capacity. ARM toolchains work but are slightly less battle-tested. Provisioning sometimes returns "out of capacity" — retry / change region. |
| **VM.Standard.E2.1.Micro** (AMD) | 1 GB RAM ×2, forever | x86 (most mature toolchains) but only 1 GB — **add swap** (provision.sh does). What this project runs in production. |

## Steps

```bash
# 0. One-time: install + configure the OCI CLI
#    bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
#    oci setup config

# 1. Create the instance + open the firewall
export COMPARTMENT_ID=ocid1.compartment.oc1..xxxx
export SUBNET_ID=ocid1.subnet.oc1..xxxx
export AVAILABILITY_DOMAIN="xxxx:AP-SYDNEY-1-AD-1"
export IMAGE_ID=ocid1.image.oc1..xxxx          # Canonical Ubuntu 22.04
export SSH_PUBKEY=~/.ssh/id_ed25519.pub
bash 01-create-instance.sh

# 2. SSH in and provision
scp -i <key> -r ../../ ubuntu@<public-ip>:~/arduino-compile-service
ssh -i <key> ubuntu@<public-ip>
sudo COMPILE_TOKEN=$(openssl rand -hex 24) \
     DOMAIN=<dash-ip>.sslip.io \
     bash ~/arduino-compile-service/deploy/common/provision.sh
```

## The Oracle-specific gotcha: the VCN Security List

Opening the OS firewall is **not enough** — Oracle blocks all inbound except SSH
at the **VCN Security List** (cloud network layer). Add ingress rules for TCP
**443** and **80** (source `0.0.0.0/0`):

- Console: *Networking → Virtual Cloud Networks → your VCN → Subnet → Security →
  Security List → Add Ingress Rules.*
- Or via CLI — see `01-create-instance.sh`, which appends the rules with `jq`.

Until this is done you'll get a TLS/connection timeout from outside even though
SSH works and Caddy is running. (Let's Encrypt also needs 80/443 to issue the
cert.)

## Keep it alive
Oracle reclaims *idle* Always-Free VMs. Enable the keep-alive timer so the box
stays active and the cache stays warm:

```bash
sudo cp ../../systemd/keepalive.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now keepalive.timer
```
