# PocketStudio - Google Cloud Marketplace

AI-powered image generation platform for Google Kubernetes Engine.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![GCP Marketplace](https://img.shields.io/badge/GCP-Marketplace-4285F4.svg)](https://console.cloud.google.com/marketplace)

## Overview

PocketStudio is an enterprise-grade AI image generation platform that runs entirely in your GKE cluster with complete data isolation. Generate images using the nano-banana AI model with automatic Workload Identity integration.

### Features

- 🎨 **AI Image Generation** - Powered by nano-banana via fal.ai
- 🔐 **Workload Identity** - No API keys needed for Google services
- 📦 **Complete Stack** - Includes MongoDB, Redis, and all dependencies
- 🪣 **Cloud Storage** - Images stored in your GCS bucket
- 💰 **Usage-based Billing** - Pay only for what you use ($1.37/hour per replica)
- 🔒 **Data Isolation** - All data stays in your infrastructure

## Prerequisites

Before deploying PocketStudio, ensure you have:

1. **GKE Cluster**
   - Workload Identity enabled (automatic in GKE 1.19+)
   - Minimum: 2 nodes, 4 CPU, 8GB RAM per node
   - `gcloud container clusters create` or existing cluster

2. **fal.ai Account**
   - Sign up: https://fal.ai
   - Get API key: https://fal.ai/dashboard
   - Add payment method

3. **Google Cloud Storage Bucket**
```bash
   gsutil mb -p YOUR_PROJECT_ID gs://pocketstudio-images-UNIQUE
```

4. **Required APIs** (enabled automatically by deployer)
   - Vertex AI API
   - Cloud Storage API
   - IAM API

## Quick Start (Cloud Console)

1. Go to [Google Cloud Marketplace](https://console.cloud.google.com/marketplace)
2. Search for "PocketStudio"
3. Click **"Configure"**
4. Fill in required fields:
   - Application name
   - Namespace
   - fal.ai API key
   - GCS bucket name
5. Click **"Deploy"**

## Command-Line Deployment

### Method 1: Using mpdev (Recommended for testing)
```bash
# Install mpdev
docker pull gcr.io/cloud-marketplace-tools/k8s/dev:latest

# Create mpdev wrapper
cat > mpdev <<'SCRIPT'
#!/bin/bash
docker run --rm --net=host \
  -v "$HOME/.config/gcloud":/root/.config/gcloud \
  -v "$HOME/.kube":/root/.kube \
  -v "$(pwd)":/data \
  gcr.io/cloud-marketplace-tools/k8s/dev:latest "$@"
SCRIPT
chmod +x mpdev

# Clone this repository
git clone https://github.com/wohlig/pocketstudio-k8s-marketplace.git
cd pocketstudio-k8s-marketplace

# Deploy with mpdev
./mpdev install \
  --deployer=us-docker.pkg.dev/confixa-public/pocketstudio/deployer:1.0 \
  --parameters='{"name":"pocketstudio-1","namespace":"pocketstudio","customer.falKey":"YOUR_FAL_KEY","customer.gcpBucket":"YOUR_BUCKET_NAME"}'
```

### Method 2: Using kubectl directly
```bash
# 1. Set environment variables
export PROJECT_ID="your-gcp-project-id"
export CLUSTER_NAME="your-cluster-name"
export ZONE="us-central1-a"
export APP_INSTANCE_NAME="pocketstudio"
export NAMESPACE="pocketstudio"
export FAL_KEY="your-fal-api-key"
export GCS_BUCKET="your-bucket-name"

# 2. Get cluster credentials
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT_ID

# 3. Create namespace
kubectl create namespace $NAMESPACE

# 4. Create GCP service account for Workload Identity
gcloud iam service-accounts create pocketstudio \
  --display-name="PocketStudio Service Account" \
  --project=$PROJECT_ID

# Grant permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# 5. Create Kubernetes service account
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_INSTANCE_NAME}-sa
  namespace: ${NAMESPACE}
  annotations:
    iam.gke.io/gcp-service-account: pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com
YAML

# 6. Bind Workload Identity
gcloud iam service-accounts add-iam-policy-binding \
  pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${APP_INSTANCE_NAME}-sa]"

# 7. Create secrets
kubectl create secret generic ${APP_INSTANCE_NAME}-secrets \
  --from-literal=fal-key="${FAL_KEY}" \
  --from-literal=gcp-bucket="${GCS_BUCKET}" \
  --from-literal=gcp-project="${PROJECT_ID}" \
  -n ${NAMESPACE}

# 8. Clone repository and deploy
git clone https://github.com/wohlig/pocketstudio-k8s-marketplace.git
cd pocketstudio-k8s-marketplace

# Set image variables
export IMAGE_POCKETSTUDIO="us-docker.pkg.dev/confixa-public/pocketstudio/backend:1.0"
export IMAGE_FRONTEND="us-docker.pkg.dev/confixa-public/pocketstudio/frontend:1.0"
export REPLICAS=1

# Deploy all components
envsubst < manifests/mongodb.yaml | kubectl apply -f -
envsubst < manifests/redis.yaml | kubectl apply -f -
envsubst < manifests/deployment.yaml | kubectl apply -f -
envsubst < manifests/backend-service.yaml | kubectl apply -f -
envsubst < manifests/frontend-deployment.yaml | kubectl apply -f -
envsubst < manifests/frontend-service.yaml | kubectl apply -f -
envsubst < manifests/application.yaml | kubectl apply -f -

# 9. Wait for deployment
kubectl wait --for=condition=available deployment/${APP_INSTANCE_NAME} -n ${NAMESPACE} --timeout=300s
kubectl wait --for=condition=available deployment/${APP_INSTANCE_NAME}-frontend -n ${NAMESPACE} --timeout=300s

# 10. Get LoadBalancer IP
kubectl get svc ${APP_INSTANCE_NAME}-frontend-svc -n ${NAMESPACE}
```

### Method 3: Using Helm (Alternative)
```bash
# Coming soon - Helm chart available at:
# helm repo add pocketstudio https://charts.pocketstudio.io
# helm install pocketstudio pocketstudio/pocketstudio
```

## Accessing PocketStudio

After deployment completes:
```bash
# Get the frontend URL
FRONTEND_IP=$(kubectl get svc pocketstudio-frontend-svc -n pocketstudio -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "PocketStudio is accessible at: http://${FRONTEND_IP}"
```

Open your browser and navigate to the displayed URL.

## Configuration

### Environment Variables

PocketStudio supports the following configuration options:

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `FAL_KEY` | fal.ai API key | Yes | - |
| `GCP_BUCKET` | GCS bucket name | Yes | - |
| `GCP_PROJECT` | GCP project ID | No | Auto-detected |
| `REPLICAS` | Number of instances | No | 2 |

### Resource Requirements

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Backend | 1 core | 2 GB | - |
| Frontend | 100m | 128 MB | - |
| MongoDB | 250m | 512 MB | 20 GB |
| Redis | 100m | 128 MB | - |

### Scaling

To scale PocketStudio:
```bash
kubectl scale deployment pocketstudio -n pocketstudio --replicas=3
kubectl scale deployment pocketstudio-frontend -n pocketstudio --replicas=3
```

**Note:** You're billed $1.37/hour per backend replica.

## Monitoring
```bash
# View all resources
kubectl get all -n pocketstudio

# Check pod status
kubectl get pods -n pocketstudio

# View logs
kubectl logs -f deployment/pocketstudio -n pocketstudio

# Check service endpoints
kubectl get svc -n pocketstudio
```

## Troubleshooting

### Pods not starting
```bash
# Describe the pod
kubectl describe pod -n pocketstudio <pod-name>

# Check events
kubectl get events -n pocketstudio --sort-by='.lastTimestamp'
```

### Common Issues

**Issue:** Image pull errors
```bash
# Solution: Grant Artifact Registry access
NODE_SA=$(gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE --format="value(nodeConfig.serviceAccount)")

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${NODE_SA}" \
  --role="roles/artifactregistry.reader"
```

**Issue:** Workload Identity not working
```bash
# Verify annotation
kubectl get sa pocketstudio-sa -n pocketstudio -o yaml | grep iam.gke.io

# Verify binding
gcloud iam service-accounts get-iam-policy \
  pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com
```

**Issue:** GCS bucket access denied
```bash
# Verify bucket exists
gsutil ls gs://your-bucket-name

# Check permissions
gsutil iam get gs://your-bucket-name
```

## Uninstalling
```bash
# Delete all resources
kubectl delete namespace pocketstudio

# Delete GCS bucket (optional)
gsutil rm -r gs://your-bucket-name

# Delete GCP service account (optional)
gcloud iam service-accounts delete pocketstudio@${PROJECT_ID}.iam.gserviceaccount.com
```

## Pricing

### Software License
- **$1.37/hour per replica** (~$1,000/month for 1 replica running 24/7)
- Billed through Google Cloud Marketplace

### Your Infrastructure Costs (billed separately)
- **GKE Cluster:** ~$150-300/month (you pay Google directly)
- **fal.ai API:** ~$0.02 per image (you pay fal.ai directly)
- **Gemini API:** Minimal cost (you pay Google directly)
- **Cloud Storage:** ~$0.02/GB/month (you pay Google directly)

**Total estimated:** ~$1,200-1,500/month for typical usage

## Architecture
```
┌─────────────────────────────────┐
│   LoadBalancer (Frontend)       │
│   Port 80                        │
└────────────┬────────────────────┘
             │
    ┌────────▼─────────┐
    │  Frontend Pods   │
    │  (React/Vue)     │
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  ClusterIP       │
    │  (Backend API)   │
    └────────┬─────────┘
             │
    ┌────────▼─────────┐
    │  Backend Pods    │
    │  (Node.js API)   │
    └──┬──────────┬────┘
       │          │
  ┌────▼──┐  ┌───▼───┐
  │MongoDB│  │ Redis │
  └───────┘  └───────┘
```

## Support

- **Email:** support@wohlig.com
- **Documentation:** https://github.com/wohlig/pocketstudio
- **Issues:** https://github.com/wohlig/pocketstudio/issues
- **Response Time:** Within 24 hours

## License

Apache License 2.0 - See [LICENSE](LICENSE) file for details.

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## Security

Found a security issue? Please email security@wohlig.com instead of using the issue tracker.

---

**Made with ❤️ by [Wohlig Transformation](https://wohlig.com)**
