#!/usr/bin/env bash
#
# Create an AWS EC2 free-tier instance for the compile service: key pair +
# security group (22/80/443) + the smallest free instance, latest Ubuntu 22.04.
# Requires the AWS CLI (`aws configure`).
#
# Env: AWS_REGION, KEY_NAME (default arduino-compiler), INSTANCE_TYPE (t2.micro)
# Optional (enables cloud-init self-provisioning): COMPILE_TOKEN, DOMAIN
set -euo pipefail

REGION="${AWS_REGION:?set AWS_REGION}"
KEY_NAME="${KEY_NAME:-arduino-compiler}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
SG_NAME="${SG_NAME:-arduino-compiler-sg}"

echo "==> Latest Ubuntu 22.04 AMI (via SSM)"
AMI=$(aws ssm get-parameters --region "$REGION" \
  --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
  --query 'Parameters[0].Value' --output text)

echo "==> Key pair"
if [ ! -f "${KEY_NAME}.pem" ]; then
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
  chmod 600 "${KEY_NAME}.pem"
fi

echo "==> Security group (22/80/443)"
SG_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$SG_NAME" \
  --description "Arduino compile service" --query 'GroupId' --output text 2>/dev/null \
  || aws ec2 describe-security-groups --region "$REGION" --group-names "$SG_NAME" \
       --query 'SecurityGroups[0].GroupId' --output text)
for port in 22 80 443; do
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port "$port" --cidr 0.0.0.0/0 2>/dev/null || true
done

# Optional cloud-init self-provisioning
USER_DATA_ARG=()
if [ -n "${COMPILE_TOKEN:-}" ] && [ -n "${DOMAIN:-}" ]; then
  echo "==> Rendering cloud-init (self-provision on boot)"
  tmp=$(mktemp)
  sed -e "s|__COMPILE_TOKEN__|${COMPILE_TOKEN}|" -e "s|__DOMAIN__|${DOMAIN}|" \
      "$(dirname "$0")/user-data.sh" > "$tmp"
  USER_DATA_ARG=(--user-data "file://$tmp")
fi

echo "==> Launching ${INSTANCE_TYPE}"
IID=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" \
  --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" "${USER_DATA_ARG[@]}" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=arduino-compiler}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --region "$REGION" --instance-ids "$IID"
IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "==> Running. Instance $IID  Public IP: $IP  Key: ${KEY_NAME}.pem"
