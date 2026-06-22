# Deploy on Azure (VM Free Tier)

Azure's free account includes **750 h/month of a B1s VM for 12 months** (1 vCPU,
1 GB) — comparable to AWS. Great for a demo; not permanent (Oracle wins there).
Azure's CLI makes VM + firewall the least fuss of the three.

## Steps

```bash
# 0. One-time: az login

export LOCATION=centralindia
export RG=arduino-compiler-rg
bash 01-create-instance.sh        # creates RG, VM, opens 22/80/443, prints IP

# 1. Provision over SSH
scp -r ../../ azureuser@<public-ip>:~/arduino-compile-service
ssh azureuser@<public-ip>
sudo COMPILE_TOKEN=$(openssl rand -hex 24) DOMAIN=<dash-ip>.sslip.io \
     bash ~/arduino-compile-service/deploy/common/provision.sh
```

### Fully automated (cloud-init)
`01-create-instance.sh` passes `cloud-init.yaml` via `--custom-data` when
`COMPILE_TOKEN` and `DOMAIN` are set, so the VM self-provisions on first boot.

## Azure-specific notes
- The cloud network layer is the **Network Security Group (NSG)**. `az vm
  open-port` (used in the script) edits it. As with the others, 80/443 must be
  open here *and* in the OS firewall, or HTTPS times out and the cert can't issue.
- `--size Standard_B1s` is the free-eligible size; `1 GB` RAM → `provision.sh`'s
  swap matters for ESP32.
- Use a **static public IP** if you want the address to persist.
- Free tier ends after 12 months — set a **budget alert**.
