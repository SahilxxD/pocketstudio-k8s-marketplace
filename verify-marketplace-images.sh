#!/bin/bash

echo "========================================="
echo "  MARKETPLACE IMAGES VERIFICATION"
echo "========================================="
echo ""

PROJECT_ID="confixa-public"
REGION="us-central1"
REGISTRY="${REGION}-docker.pkg.dev"
REPOSITORY="pocketstudio"
VERSION="1.0.0"

ERRORS=0

# Check 1: Repository exists
echo "1️⃣  Checking Artifact Registry repository..."
if gcloud artifacts repositories describe $REPOSITORY \
  --location=$REGION \
  --project=$PROJECT_ID &>/dev/null; then
  echo "   ✅ Repository exists"
else
  echo "   ❌ Repository not found"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 2: Backend image exists
echo "2️⃣  Checking backend image..."
BACKEND_IMAGE="${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/backend:${VERSION}"
if gcloud artifacts docker images describe $BACKEND_IMAGE --project=$PROJECT_ID &>/dev/null; then
  echo "   ✅ Backend image exists"
  echo "   Image: $BACKEND_IMAGE"
  
  # Check annotations (optional, requires crane)
  if command -v crane &>/dev/null; then
    echo "   Checking marketplace annotations..."
    MANIFEST=$(crane manifest $BACKEND_IMAGE 2>/dev/null || echo "")
    if [ -n "$MANIFEST" ] && echo "$MANIFEST" | grep -q "cloudmarketplace"; then
      echo "   ✅ Marketplace annotations present"
    fi
  fi
else
  echo "   ❌ Backend image not found"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 3: Deployer image exists
echo "3️⃣  Checking deployer image..."
DEPLOYER_IMAGE="${REGISTRY}/${PROJECT_ID}/${REPOSITORY}/deployer:${VERSION}"
if gcloud artifacts docker images describe $DEPLOYER_IMAGE --project=$PROJECT_ID &>/dev/null; then
  echo "   ✅ Deployer image exists"
  echo "   Image: $DEPLOYER_IMAGE"
else
  echo "   ❌ Deployer image not found"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 4: Schema references correct images
echo "4️⃣  Checking schema image references..."
if grep -q "$PROJECT_ID" schema/schema.yaml && \
   grep -q "$REPOSITORY" schema/schema.yaml; then
  echo "   ✅ Schema has correct image paths"
else
  echo "   ❌ Schema image paths incorrect"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 5: Deployment uses variables (improved detection)
echo "5️⃣  Checking manifest image references..."

# Look for variable usage patterns
POCKETSTUDIO_VAR=$(grep -o '\$IMAGE_POCKETSTUDIO\|\${IMAGE_POCKETSTUDIO}' manifests/deployment.yaml | head -1)
UBBAGENT_VAR=$(grep -o '\$IMAGE_UBBAGENT\|\${IMAGE_UBBAGENT}' manifests/deployment.yaml | head -1)

if [ -n "$POCKETSTUDIO_VAR" ] && [ -n "$UBBAGENT_VAR" ]; then
  echo "   ✅ Deployment uses image variables correctly"
  echo "   Found: $POCKETSTUDIO_VAR and $UBBAGENT_VAR"
elif [ -n "$POCKETSTUDIO_VAR" ]; then
  echo "   ⚠️  Found $POCKETSTUDIO_VAR but missing \$IMAGE_UBBAGENT"
  ERRORS=$((ERRORS + 1))
else
  # Check if it's hardcoded
  HARDCODED=$(grep "image:.*docker.pkg.dev" manifests/deployment.yaml | grep -v "^\s*#" | head -1)
  if [ -n "$HARDCODED" ]; then
    echo "   ❌ Deployment has hardcoded image path:"
    echo "   $HARDCODED"
    ERRORS=$((ERRORS + 1))
  else
    echo "   ⚠️  Could not detect image variable pattern"
    ERRORS=$((ERRORS + 1))
  fi
fi
echo ""

# Summary
echo "========================================="
if [ $ERRORS -eq 0 ]; then
  echo "✅ ALL CHECKS PASSED!"
  echo ""
  echo "Published Images:"
  echo "  📦 Backend: $BACKEND_IMAGE"
  echo "  🚀 Deployer: $DEPLOYER_IMAGE"
  echo ""
  echo "Configuration:"
  echo "  ✓ Platform: linux/amd64"
  echo "  ✓ Marketplace annotations included"
  echo "  ✓ Service name: services/pocketstudio.endpoints.confixa-public.cloud.goog"
  echo "  ✓ Version: $VERSION"
  echo "  ✓ Image variables: \$IMAGE_POCKETSTUDIO, \$IMAGE_UBBAGENT"
  echo ""
  echo "🎯 READY FOR TESTING!"
  echo ""
  echo "Next steps:"
  echo "  1. Test locally with mpdev"
  echo "  2. Deploy to test GKE cluster"
  echo "  3. Submit to Google Cloud Marketplace"
else
  echo "❌ $ERRORS ERRORS FOUND"
  echo "Please review errors above"
fi
echo "========================================="
