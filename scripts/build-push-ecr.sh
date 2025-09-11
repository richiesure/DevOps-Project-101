#!/bin/bash
set -euxo pipefail

# Install basics + docker + SSM agent is preinstalled on AL2023
dnf update -y
dnf install -y docker jq amazon-ssm-agent
systemctl enable --now docker
usermod -aG docker ec2-user || true

# Log in to ECR
AWS_REGION="$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
ACCOUNT_ID="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId)"
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${ECR_URL}"

# Fetch DB creds from Secrets Manager
DB_SECRET_NAME="${db_secret_name}"
DB_JSON=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION")
DB_PASSWORD=$(echo "$DB_JSON" | jq -r .password)

# Pull & run the app image
IMAGE_REPO="${ecr_repo}"
IMAGE_TAG="${app_image_tag}"

docker pull "${IMAGE_REPO}:${IMAGE_TAG}"

# App env
export SPRING_DATASOURCE_URL="jdbc:mysql://${db_host}:3306/${db_name}"
export SPRING_DATASOURCE_USERNAME="${db_username}"
export SPRING_DATASOURCE_PASSWORD="${DB_PASSWORD}"
export JAVA_OPTS=""

# Run container
docker run -d --restart unless-stopped --name app \
  -e SPRING_DATASOURCE_URL \
  -e SPRING_DATASOURCE_USERNAME \
  -e SPRING_DATASOURCE_PASSWORD \
  -e JAVA_OPTS \
  -p 8080:8080 \
  "${IMAGE_REPO}:${IMAGE_TAG}"
