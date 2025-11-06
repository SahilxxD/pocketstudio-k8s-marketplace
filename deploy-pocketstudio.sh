#!/bin/bash
set -e

# Configuration
export PROJECT_ID="confixa-public"
export ZONE="us-central1-a"
export CLUSTER_NAME="pocketstudio-test-mini"
export APP_INSTANCE_NAME="pocketstudio"
export NAMESPACE="pocketstudio-test"
export IMAGE_POCKETSTUDIO="us-central1-docker.pkg.dev/${PROJECT_ID}/pocketstudio/backend:1.0.0"
export IMAGE_UBBAGENT="gcr.io/cloud-marketplace-tools/metering/ubbagent:latest"
export REPLICAS=1
export REPORTING_SECRET="pocketstudio-reporting"

echo "🚀 Deploying PocketStudio to GKE"
echo "================================"
echo ""

# Get fal.ai key
if [ -z "$FAL_KEY" ]; then
  read -sp "Enter your fal.ai API key: " FAL_KEY
  echo ""
fi

export CUSTOMER_FAL_KEY="$FAL_KEY"
export CUSTOMER_GCP_BUCKET="pocketstudio-test-$(date +%s)"
export CUSTOMER_GCP_PROJECT="$PROJECT_ID"

# Grant GKE nodes Artifact Registry access
echo "1️⃣  Configuring Artifact Registry access..."
NODE_SA=$(gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE \
  --format="value(nodeConfig.serviceAccount)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${NODE_SA}" \
  --role="roles/artifactregistry.reader" \
  --condition=None \
  2>/dev/null || true

echo "   ✅ Permissions configured"
echo ""

# Create GCS bucket
echo "2️⃣  Creating GCS bucket..."
gsutil mb -p $PROJECT_ID -c STANDARD -l us-central1 gs://${CUSTOMER_GCP_BUCKET} 2>/dev/null || echo "   Bucket already exists"
echo "   ✅ Bucket: gs://${CUSTOMER_GCP_BUCKET}"
echo ""

# Create namespace
echo "3️⃣  Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "   ✅ Namespace created"
echo ""

# Create GCP service account for Workload Identity
echo "4️⃣  Setting up Workload Identity..."
GSA_EMAIL="pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create pocketstudio \
  --display-name="PocketStudio Service Account" \
  --project=$PROJECT_ID 2>/dev/null || echo "   Service account exists"

# Grant permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/storage.objectAdmin" \
  --condition=None 2>/dev/null || true

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/aiplatform.user" \
  --condition=None 2>/dev/null || true

echo "   ✅ GCP service account configured"
echo ""

# Create Kubernetes service account
echo "5️⃣  Creating Kubernetes service account..."
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_INSTANCE_NAME}-sa
  namespace: ${NAMESPACE}
  annotations:
    iam.gke.io/gcp-service-account: ${GSA_EMAIL}
YAML

# Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding ${GSA_EMAIL} \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${APP_INSTANCE_NAME}-sa]" \
  --project=$PROJECT_ID 2>/dev/null || true

echo "   ✅ Kubernetes service account created"
echo ""

# Create secrets
echo "6️⃣  Creating secrets..."
kubectl create secret generic ${APP_INSTANCE_NAME}-secrets \
  --from-literal=fal-key="${CUSTOMER_FAL_KEY}" \
  --from-literal=gcp-bucket="${CUSTOMER_GCP_BUCKET}" \
  --from-literal=gcp-project="${CUSTOMER_GCP_PROJECT}" \
  -n ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic ${REPORTING_SECRET} \
  --from-literal=reporting-key="test-key-$(openssl rand -hex 16)" \
  --from-literal=consumer-id="test-consumer-$(date +%s)" \
  -n ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo "   ✅ Secrets created"
echo ""

# Deploy MongoDB
echo "7️⃣  Deploying MongoDB..."
envsubst < manifests/mongodb.yaml | kubectl apply -f -

echo "   Waiting for MongoDB..."
kubectl wait --for=condition=available deployment/${APP_INSTANCE_NAME}-mongodb \
  -n ${NAMESPACE} \
  --timeout=300s

echo "   ✅ MongoDB ready"
echo ""

# Deploy Redis
echo "8️⃣  Deploying Redis..."
envsubst < manifests/redis.yaml | kubectl apply -f -

echo "   Waiting for Redis..."
kubectl wait --for=condition=available deployment/${APP_INSTANCE_NAME}-redis \
  -n ${NAMESPACE} \
  --timeout=120s

echo "   ✅ Redis ready"
echo ""

# Deploy UBB Agent config
echo "9️⃣  Configuring usage reporting..."
envsubst < manifests/ubbagent-config.yaml | kubectl apply -f -
echo "   ✅ UBB Agent configured"
echo ""

# Deploy application
echo "🔟  Deploying PocketStudio application..."
envsubst < manifests/deployment.yaml | kubectl apply -f -
envsubst < manifests/service.yaml | kubectl apply -f -
envsubst < manifests/application.yaml | kubectl apply -f -

echo "   ✅ Application deployed"
echo ""

# Wait for deployment
echo "1️⃣1️⃣  Waiting for application pods..."
kubectl wait --for=condition=available deployment/${APP_INSTANCE_NAME} \
  -n ${NAMESPACE} \
  --timeout=300s

echo "   ✅ Application ready"
echo ""

# Get status
echo "================================"
echo "✅ DEPLOYMENT COMPLETE!"
echo "================================"
echo ""

echo "📊 Status:"
kubectl get pods -n ${NAMESPACE}
echo ""

echo "🌐 Getting LoadBalancer IP..."
for i in {1..30}; do
  EXTERNAL_IP=$(kubectl get svc ${APP_INSTANCE_NAME}-svc -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  
  if [ -n "$EXTERNAL_IP" ]; then
    echo ""
    echo "✅ Application accessible at:"
    echo "   http://${EXTERNAL_IP}"
    echo ""
    break
  fi
  
  echo "   Waiting for IP... ($i/30)"
  sleep 10
done

echo "📋 Useful commands:"
echo "   View pods:  kubectl get pods -n ${NAMESPACE}"
echo "   View logs:  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_INSTANCE_NAME} -f"
echo "   Get IP:     kubectl get svc ${APP_INSTANCE_NAME}-svc -n ${NAMESPACE}"
echo ""

