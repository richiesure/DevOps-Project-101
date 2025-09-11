#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-eu-west-2}"
REPO_NAME="${2:-java-login-app}"
TAG="${3:-$(git rev-parse --short HEAD)}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr describe-repositories --repository-names "${REPO_NAME}" --region "${REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${REPO_NAME}" --region "${REGION}" >/dev/null

aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URL}"

docker build -t "${REPO_NAME}:${TAG}" .
docker tag "${REPO_NAME}:${TAG}" "${ECR_URL}/${REPO_NAME}:${TAG}"
docker push "${ECR_URL}/${REPO_NAME}:${TAG}"

echo "Pushed: ${ECR_URL}/${REPO_NAME}:${TAG}"
