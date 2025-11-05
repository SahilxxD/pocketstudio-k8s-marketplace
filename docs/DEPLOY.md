# PocketStudio - Command-Line Deployment Guide

Complete guide for deploying PocketStudio on Google Kubernetes Engine using command-line tools.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Setup](#detailed-setup)
4. [Post-Deployment](#post-deployment)
5. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

Install the following tools before proceeding:
```bash
# Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# kubectl
gcloud components install kubectl

# Verify installations
gcloud version
kubectl version --client
```

### Required Resources

- ✅ GCP Project with billing enabled
- ✅ GKE cluster (or create new one)
- ✅ fal.ai API key from https://fal.ai/dashboard
- ✅ Google Cloud Storage bucket

---

## Quick Start

### 1-Minute Deploy (Existing Cluster)
```bash
# Set variables
export PROJECT_ID="your-gcp-project"
export CLUSTER_NAME="your-cluster"
export ZONE="us-central1-a"
export FAL_KEY="your-fal-key"
export BUCKET="your-bucket-name"

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID

# Clone and deploy
git clone https://github.com/wohlig/pocketstudio-k8s-marketplace.git
cd pocketstudio-k8s-marketplace
./quick-deploy.sh --fal-key=$FAL_KEY --bucket=$BUCKET
```

---

## Detailed Setup

### Step 1: Create GKE Cluster (if needed)
```bash
export PROJECT_ID="your-gcp-project"
export CLUSTER_NAME="pocketstudio-cluster"
export ZONE="us-central1-a"

# Create cluster with Workload Identity
gcloud container clusters create $CLUSTER_NAME \
  --zone=$ZONE \
  --machine-type=e2-standard-4 \
  --num-nodes=2 \
  --enable-autorepair \
  --enable-autoupgrade \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --addons=HorizontalPodAutoscaling,GcePersistentDiskCsiDriver \
  --project=$PROJECT_ID

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT_ID
```

**Cost:** ~$200-300/month for this cluster configuration.

### Step 2: Create Cloud Storage Bucket
```bash
export BUCKET="pocketstudio-images-$(date +%s)"
export REGION="us-central1"

# Create bucket
gsutil mb -p $PROJECT_ID -l $REGION gs://${BUCKET}

# Verify
gsutil ls gs://${BUCKET}
```

### Step 3: Set Up Workload Identity
```bash
# Create GCP service account
gcloud iam service-accounts create pocketstudio \
  --display-name="PocketStudio Service Account" \
  --project=$PROJECT_ID

# Grant storage permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Grant Vertex AI permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"
```

### Step 4: Deploy PocketStudio
```bash
export APP_INSTANCE_NAME="pocketstudio"
export NAMESPACE="pocketstudio"
export FAL_KEY="your-fal-api-key"  # From https://fal.ai/dashboard

# Create namespace
kubectl create namespace $NAMESPACE

# Create Kubernetes service account
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_INSTANCE_NAME}-sa
  namespace: ${NAMESPACE}
  annotations:
    iam.gke.io/gcp-service-account: pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com
YAML

# Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding \
  pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${APP_INSTANCE_NAME}-sa]" \
  --project=$PROJECT_ID

# Create secrets
kubectl create secret generic ${APP_INSTANCE_NAME}-secrets \
  --from-literal=fal-key="${FAL_KEY}" \
  --from-literal=gcp-bucket="${BUCKET}" \
  --from-literal=gcp-project="${PROJECT_ID}" \
  -n ${NAMESPACE}

# Clone repository
git clone https://github.com/wohlig/pocketstudio-k8s-marketplace.git
cd pocketstudio-k8s-marketplace

# Set image variables
export IMAGE_POCKETSTUDIO="us-docker.pkg.dev/confixa-public/pocketstudio/backend:1.0"
export IMAGE_FRONTEND="us-docker.pkg.dev/confixa-public/pocketstudio/frontend:1.0"
export REPLICAS=1

# Grant GKE nodes access to images
NODE_SA=$(gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE \
  --format="value(nodeConfig.serviceAccount)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${NODE_SA}" \
  --role="roles/artifactregistry.reader"

# Deploy all components
kubectl apply -f manifests/mongodb.yaml -n $NAMESPACE
kubectl apply -f manifests/redis.yaml -n $NAMESPACE
envsubst < manifests/deployment.yaml | kubectl apply -f -
envsubst < manifests/backend-service.yaml | kubectl apply -f -
envsubst < manifests/frontend-deployment.yaml | kubectl apply -f -
envsubst < manifests/frontend-service.yaml | kubectl apply -f -
envsubst < manifests/application.yaml | kubectl apply -f -

echo "✅ Deployment initiated"
```

### Step 5: Wait for Deployment
```bash
# Watch deployment progress
kubectl get pods -n $NAMESPACE -w

# Wait for all pods to be ready
kubectl wait --for=condition=available deployment/pocketstudio -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/pocketstudio-frontend -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/pocketstudio-mongodb -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/pocketstudio-redis -n $NAMESPACE --timeout=120s
```

---

## Post-Deployment

### Get Access URL
```bash
# Get LoadBalancer IP (may take 2-5 minutes)
kubectl get svc pocketstudio-frontend-svc -n $NAMESPACE

# Wait for EXTERNAL-IP
EXTERNAL_IP=$(kubectl get svc pocketstudio-frontend-svc -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "PocketStudio URL: http://${EXTERNAL_IP}"
```

### Verify Deployment
```bash
# Check all resources
kubectl get all -n $NAMESPACE

# Test health endpoint
curl http://${EXTERNAL_IP}/health

# View logs
kubectl logs -f deployment/pocketstudio -n $NAMESPACE
```

### Configure DNS (Optional)
```bash
# Point your domain to the LoadBalancer IP
# Example: pocketstudio.yourdomain.com -> EXTERNAL_IP

# Update DNS A record
# Type: A
# Name: pocketstudio
# Value: <EXTERNAL_IP>
# TTL: 300
```

---

## Monitoring & Management

### View Logs
```bash
# Backend logs
kubectl logs -f deployment/pocketstudio -n $NAMESPACE

# Frontend logs
kubectl logs -f deployment/pocketstudio-frontend -n $NAMESPACE

# MongoDB logs
kubectl logs -f deployment/pocketstudio-mongodb -n $NAMESPACE

# All logs
kubectl logs -f -l app.kubernetes.io/name=pocketstudio -n $NAMESPACE
```

### Scale Application
```bash
# Scale backend
kubectl scale deployment pocketstudio -n $NAMESPACE --replicas=3

# Scale frontend
kubectl scale deployment pocketstudio-frontend -n $NAMESPACE --replicas=2

# Check status
kubectl get deployments -n $NAMESPACE
```

**Note:** You're billed $1.37/hour per backend replica.

### Update Configuration
```bash
# Update secrets
kubectl create secret generic pocketstudio-secrets \
  --from-literal=fal-key="new-key" \
  --from-literal=gcp-bucket="${BUCKET}" \
  --from-literal=gcp-project="${PROJECT_ID}" \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secrets
kubectl rollout restart deployment/pocketstudio -n $NAMESPACE
```

---

## Troubleshooting

### Pods Not Starting
```bash
# Describe pod
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=pocketstudio-api -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD_NAME -n $NAMESPACE

# Check events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20

# View pod logs
kubectl logs $POD_NAME -n $NAMESPACE
```

### Image Pull Errors
```bash
# Verify node has access to Artifact Registry
NODE_SA=$(gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE --format="value(nodeConfig.serviceAccount)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${NODE_SA}" \
  --role="roles/artifactregistry.reader"

# Restart deployment
kubectl rollout restart deployment/pocketstudio -n $NAMESPACE
```

### Workload Identity Issues
```bash
# Check service account annotation
kubectl get sa pocketstudio-sa -n $NAMESPACE -o yaml | grep iam.gke.io

# Verify IAM binding
gcloud iam service-accounts get-iam-policy \
  pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com

# Re-bind if needed
gcloud iam service-accounts add-iam-policy-binding \
  pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/pocketstudio-sa]"
```

### Cannot Access Application
```bash
# Check LoadBalancer status
kubectl get svc pocketstudio-frontend-svc -n $NAMESPACE

# Check firewall rules
gcloud compute firewall-rules list --filter="name~gke-${CLUSTER_NAME}"

# Test internal connectivity
kubectl run test-curl --image=curlimages/curl -i --rm --restart=Never -n $NAMESPACE -- \
  curl http://pocketstudio-backend-svc:3000/health
```

### Database Connection Issues
```bash
# Check MongoDB status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=mongodb

# Test MongoDB connection
kubectl exec -it deployment/pocketstudio-mongodb -n $NAMESPACE -- mongosh --eval "db.adminCommand('ping')"

# Check Redis
kubectl exec -it deployment/pocketstudio-redis -n $NAMESPACE -- redis-cli ping
```

---

## Uninstallation

### Remove Application
```bash
# Delete namespace (removes all resources)
kubectl delete namespace $NAMESPACE

# Verify deletion
kubectl get all -n $NAMESPACE
# Should show: No resources found
```

### Clean Up GCP Resources
```bash
# Delete GCS bucket (optional, contains your images)
gsutil rm -r gs://${BUCKET}

# Delete service account (optional)
gcloud iam service-accounts delete pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com --project=$PROJECT_ID

# Delete cluster (optional)
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID
```

---

## Additional Resources

- **Main Repository:** https://github.com/wohlig/pocketstudio-k8s-marketplace
- **Support Email:** support@wohlig.com
- **fal.ai Documentation:** https://fal.ai/docs
- **GKE Documentation:** https://cloud.google.com/kubernetes-engine/docs

---

**Need help?** Email support@wohlig.com or create an issue at https://github.com/wohlig/pocketstudio-k8s-marketplace/issues
