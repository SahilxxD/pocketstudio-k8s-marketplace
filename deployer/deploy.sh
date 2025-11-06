#!/bin/bash
set -euo pipefail

echo "========================================"
echo "  PocketStudio Marketplace Deployer"
echo "  Version: 1.0.0"
echo "========================================"
echo ""

# STEP 1: EXPORT VARIABLES
echo "📋 Step 1: Loading configuration..."

export APP_INSTANCE_NAME="${name}"
export NAMESPACE="${namespace}"
export REPLICAS="${replicas:-2}"
export REPORTING_SECRET="${reportingSecret}"

# Export image variables
export IMAGE_POCKETSTUDIO="${image_pocketstudio}"
export IMAGE_FRONTEND="${image_frontend}"
export IMAGE_UBBAGENT="gcr.io/cloud-marketplace-tools/metering/ubbagent:latest"

# Customer configuration
export CUSTOMER_FAL_KEY="${customer_falKey}"
export CUSTOMER_GCP_BUCKET="${customer_gcpBucket}"

echo "   App Name: $APP_INSTANCE_NAME"
echo "   Namespace: $NAMESPACE"
echo "   Replicas: $REPLICAS"
echo "   Backend Image: $IMAGE_POCKETSTUDIO"
echo "   Frontend Image: $IMAGE_FRONTEND"
echo "   UBB Agent Image: $IMAGE_UBBAGENT"
echo "   GCS Bucket: $CUSTOMER_GCP_BUCKET"
echo ""

# STEP 2: AUTO-DETECT GCP PROJECT
echo "📋 Step 2: Detecting GCP project..."

if [ -z "${customer_gcpProject:-}" ] || [ "${customer_gcpProject}" = "" ]; then
  DETECTED_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
  if [ -z "$DETECTED_PROJECT" ]; then
    echo "   ❌ ERROR: Could not auto-detect GCP project"
    exit 1
  fi
  export CUSTOMER_GCP_PROJECT="$DETECTED_PROJECT"
  echo "   ✅ Auto-detected: $CUSTOMER_GCP_PROJECT"
else
  export CUSTOMER_GCP_PROJECT="${customer_gcpProject}"
  echo "   ✅ Using provided: $CUSTOMER_GCP_PROJECT"
fi
echo ""

# STEP 3: VALIDATE PREREQUISITES
echo "📋 Step 3: Validating prerequisites..."

if [ -z "$CUSTOMER_FAL_KEY" ]; then
  echo "   ❌ ERROR: fal.ai API key not provided"
  exit 1
fi
echo "   ✅ fal.ai API key provided"

if [ -z "$CUSTOMER_GCP_BUCKET" ]; then
  echo "   ❌ ERROR: GCS bucket name not provided"
  exit 1
fi
echo "   ✅ GCS bucket name provided"

if gsutil ls "gs://${CUSTOMER_GCP_BUCKET}" &>/dev/null; then
  echo "   ✅ Bucket verified: gs://${CUSTOMER_GCP_BUCKET}"
else
  echo "   ❌ ERROR: Bucket gs://${CUSTOMER_GCP_BUCKET} does not exist"
  exit 1
fi
echo ""

# STEP 4: ENABLE REQUIRED APIS
echo "📋 Step 4: Enabling required Google Cloud APIs..."
gcloud services enable aiplatform.googleapis.com storage.googleapis.com iam.googleapis.com \
  --project=$CUSTOMER_GCP_PROJECT 2>/dev/null || true
echo "   ✅ APIs enabled"
echo ""

# STEP 5: CREATE GCP SERVICE ACCOUNT
echo "📋 Step 5: Setting up Workload Identity..."
GSA_NAME="pocketstudio"
GSA_EMAIL="${GSA_NAME}@${CUSTOMER_GCP_PROJECT}.iam.gserviceaccount.com"

gcloud iam service-accounts create $GSA_NAME \
  --display-name="PocketStudio Service Account" \
  --project=$CUSTOMER_GCP_PROJECT 2>/dev/null || echo "   Service account exists"

gcloud projects add-iam-policy-binding $CUSTOMER_GCP_PROJECT \
  --member="serviceAccount:$GSA_EMAIL" \
  --role="roles/storage.objectAdmin" \
  --condition=None 2>/dev/null || true

gcloud projects add-iam-policy-binding $CUSTOMER_GCP_PROJECT \
  --member="serviceAccount:$GSA_EMAIL" \
  --role="roles/aiplatform.user" \
  --condition=None 2>/dev/null || true

echo "   ✅ GCP service account configured"
echo ""

# STEP 6: CREATE NAMESPACE
echo "📋 Step 6: Creating Kubernetes namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "   ✅ Namespace ready: $NAMESPACE"
echo ""

# STEP 7: CREATE KUBERNETES SERVICE ACCOUNT
echo "📋 Step 7: Creating Kubernetes service account..."
cat > /tmp/serviceaccount.yaml <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_INSTANCE_NAME}-sa
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: "${APP_INSTANCE_NAME}"
  annotations:
    iam.gke.io/gcp-service-account: "${GSA_EMAIL}"
YAML

kubectl apply -f /tmp/serviceaccount.yaml
echo "   ✅ Kubernetes service account created"
echo ""

# STEP 8: BIND WORKLOAD IDENTITY
echo "📋 Step 8: Binding Workload Identity..."
gcloud iam service-accounts add-iam-policy-binding $GSA_EMAIL \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${CUSTOMER_GCP_PROJECT}.svc.id.goog[${NAMESPACE}/${APP_INSTANCE_NAME}-sa]" \
  --project=$CUSTOMER_GCP_PROJECT 2>/dev/null || true
echo "   ✅ Workload Identity binding complete"
echo ""

# STEP 9: DEPLOY MONGODB
echo "📋 Step 9: Deploying MongoDB..."
envsubst < /data/manifest/mongodb.yaml | kubectl apply -f -
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=mongodb -n "$NAMESPACE" --timeout=300s || true
echo "   ✅ MongoDB deployed"
echo ""

# STEP 10: DEPLOY REDIS
echo "📋 Step 10: Deploying Redis..."
envsubst < /data/manifest/redis.yaml | kubectl apply -f -
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=redis -n "$NAMESPACE" --timeout=120s || true
echo "   ✅ Redis deployed"
echo ""

# STEP 11: CREATE SECRETS
echo "📋 Step 11: Creating secrets..."
envsubst < /data/manifest/secrets.yaml | kubectl apply -f -
echo "   ✅ Secrets created"
echo ""

# STEP 12: DEPLOY UBB AGENT CONFIG
echo "📋 Step 12: Configuring usage reporting..."
envsubst < /data/manifest/ubbagent-config.yaml | kubectl apply -f -
echo "   ✅ Usage reporting configured"
echo ""

# STEP 13: DEPLOY BACKEND APPLICATION
echo "📋 Step 13: Deploying PocketStudio backend..."
envsubst < /data/manifest/deployment.yaml | kubectl apply -f -
envsubst < /data/manifest/backend-service.yaml | kubectl apply -f -
echo "   ✅ Backend deployed"
echo ""

# STEP 14: DEPLOY FRONTEND
echo "📋 Step 14: Deploying PocketStudio frontend..."
envsubst < /data/manifest/frontend-deployment.yaml | kubectl apply -f -
envsubst < /data/manifest/frontend-service.yaml | kubectl apply -f -
echo "   ✅ Frontend deployed"
echo ""

# STEP 15: CREATE APPLICATION CR
echo "📋 Step 15: Creating Application resource..."
envsubst < /data/manifest/application.yaml | kubectl apply -f -
echo "   ✅ Application resource created"
echo ""

# STEP 16: WAIT FOR DEPLOYMENT
echo "📋 Step 16: Waiting for application to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=pocketstudio-api -n "$NAMESPACE" --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=pocketstudio-frontend -n "$NAMESPACE" --timeout=300s || true
echo ""

echo "========================================"
echo "✅ DEPLOYMENT COMPLETE!"
echo "========================================"
echo ""

# Get frontend LoadBalancer IP
echo "🌐 Getting Frontend LoadBalancer IP..."
for i in {1..30}; do
  EXTERNAL_IP=$(kubectl get svc "${APP_INSTANCE_NAME}-frontend-svc" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$EXTERNAL_IP" ]; then
    echo ""
    echo "✅ PocketStudio is accessible at:"
    echo "   http://${EXTERNAL_IP}"
    echo ""
    break
  fi
  echo "   Waiting for IP... ($i/30)"
  sleep 10
done

echo "📋 Useful Commands:"
echo "   View pods:  kubectl get pods -n $NAMESPACE"
echo "   View logs:  kubectl logs -f deployment/$APP_INSTANCE_NAME -n $NAMESPACE"
echo "   Frontend:   kubectl get svc ${APP_INSTANCE_NAME}-frontend-svc -n $NAMESPACE"
echo "   Backend:    kubectl get svc ${APP_INSTANCE_NAME}-backend-svc -n $NAMESPACE"
echo ""
echo "🎉 Enjoy using PocketStudio!"
