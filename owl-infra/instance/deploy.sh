#!/usr/bin/env bash
# Installed at /opt/owl/deploy.sh. Run on boot and by the deploy workflow (over SSM).
# Rebuilds /opt/owl/.env from SSM Parameter Store, logs in to ECR, pulls, restarts.
set -euo pipefail

OWL_DIR=/opt/owl
REGION="${AWS_REGION:-us-east-1}"
SSM_PREFIX="${OWL_SSM_PREFIX:-/owl}"

cd "$OWL_DIR"

# 1. Render .env from SSM (SecureString params under $SSM_PREFIX/)
echo "# generated $(date -u +%FT%TZ) from SSM $SSM_PREFIX" > .env.tmp
aws ssm get-parameters-by-path \
  --path "$SSM_PREFIX" --recursive --with-decryption --region "$REGION" \
  --query 'Parameters[].[Name,Value]' --output text \
| while IFS=$'\t' read -r name value; do
    echo "${name##*/}=${value}" >> .env.tmp
  done
mv .env.tmp .env
chmod 600 .env

# 2. ECR login
ECR_REGISTRY="$(grep -E '^ECR_REGISTRY=' .env | cut -d= -f2-)"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# 3. Pull and restart
docker compose --env-file .env -f docker-compose.yml pull
docker compose --env-file .env -f docker-compose.yml up -d --remove-orphans
docker image prune -f
