# Deploy on AWS (EC2 Free Tier)

AWS Free Tier gives **750 h/month for 12 months** of a `t2.micro` (x86, 1 GB) or
`t4g.small` (ARM). After 12 months it bills, so it's great for a demo / trial,
less so for a permanent host (Oracle wins there).

## Steps

```bash
# 0. One-time: aws configure   (needs an IAM user/role with EC2 permissions)

# 1. Create key pair, security group (22/80/443), and launch the instance
export AWS_REGION=ap-south-1
export KEY_NAME=arduino-compiler
bash 01-create-instance.sh        # prints the public IP + saved key path

# 2a. Provision over SSH
scp -i ${KEY_NAME}.pem -r ../../ ubuntu@<public-ip>:~/arduino-compile-service
ssh -i ${KEY_NAME}.pem ubuntu@<public-ip>
sudo COMPILE_TOKEN=$(openssl rand -hex 24) DOMAIN=<dash-ip>.sslip.io \
     bash ~/arduino-compile-service/deploy/common/provision.sh
```

### 2b. Fully automated (cloud-init)
Pass `user-data.sh` at launch (`01-create-instance.sh` does this when
`COMPILE_TOKEN` and `DOMAIN` are set) and the box self-provisions on first boot —
no SSH needed.

## AWS-specific notes
- **Security Group** is the cloud network layer (analogous to Oracle's Security
  List). `01-create-instance.sh` opens 22/80/443. Without 80/443 open here,
  HTTPS times out and the cert can't issue.
- The AMI is resolved from **SSM Public Parameters** so you always get the
  latest Ubuntu 22.04 for your region/arch.
- Assign an **Elastic IP** if you want the address (and your `sslip.io`/DNS) to
  survive a stop/start.
- Costs after the 12-month window — set a **billing alarm**.
