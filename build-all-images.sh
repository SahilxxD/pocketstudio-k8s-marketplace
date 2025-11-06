#!/bin/bash
set -e

echo "========================================="
echo "  BUILD ALL POCKETSTUDIO IMAGES"
echo "========================================="
echo ""

# Configuration
export PROJECT_ID="confixa-public"
export REGION="us"
export REGISTRY="${REGION}-docker.pkg.dev"
export REPOSITORY="pocketstudio"
export SERVICE_NAME="services/pocketstudio.endpoints.confixa-public.cloud.goog"
export VERSION="1.0.0"

echo "Registry: $REGISTRY/$PROJECT_ID/$REPOSITORY"
echo "Version: $VERSION"
echo ""

# 1. Backend
echo "1️⃣  Building backend image..."
cd ~/your-pocketstudio-backend-directory  # UPDATE THIS PATH
docker buildx build \
  --platform linux/amd64 \
  --annotation "com.googleapis.cloudmarketplace.product.service.name=${SERVICE_NAME}" \
  --annotation "com.googleapis.cloudmarketplace.product.version=${VERSION}" \
  -t ${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/backend:${VERSION} \
  --push .
echo "   ✅ Backend: ${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/backend:${VERSION}"
echo ""

# 2. Frontend
echo "2️⃣  Building frontend image..."
cd ~/your-pocketstudio-frontend-directory  # UPDATE THIS PATH
docker buildx build \
  --platform linux/amd64 \
  --annotation "com.googleapis.cloudmarketplace.product.service.name=${SERVICE_NAME}" \
  --annotation "com.googleapis.cloudmarketplace.product.version=${VERSION}" \
  -t ${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/frontend:${VERSION} \
  --push .
echo "   ✅ Frontend: ${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/frontend:${VERSION}"
echo ""

# 3. Deployer
echo "3️⃣  Building deployer image..."
cd ~/pocketstudio-k8s-marketplace
docker buildx build \
  --platform linux/amd64 \
  --annotation "com.googleapis.cloudmarketplace.product.service.name=${SERVICE_NAME}" \
  --annotation "com.googleapis.cloudmarketplace.product.version=${VERSION}" \
  -t ${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/deployer:${VERSION} \
  -f deployer/Dockerfile \
  --push .
echo "   ✅ Deployer: ${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/deployer:${VERSION}"
echo ""

echo "========================================="
echo "✅ ALL IMAGES BUILT!"
echo "========================================="
echo ""

gcloud artifacts docker images list \
  ${REGISTRY}/${PROJECT_ID}/${REPOSITORY} \
  --include-tags

echo ""
echo "🎯 Ready for marketplace deployment!"
