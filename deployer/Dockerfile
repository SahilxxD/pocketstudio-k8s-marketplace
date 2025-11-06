# Use Google's deployer base image with envsubst
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_envsubst:latest

# Copy manifests to the standard location
COPY manifests/* /data/manifest/

# Copy schema
COPY schema/schema.yaml /data/

# Copy deployment script
COPY deployer/deploy.sh /bin/deploy.sh

# Make script executable
RUN chmod +x /bin/deploy.sh

# Set entrypoint
ENTRYPOINT ["/bin/deploy.sh"]
