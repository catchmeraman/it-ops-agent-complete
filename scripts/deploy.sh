#!/bin/bash
# deploy.sh - Build ARM64 container, push to ECR, update AgentCore Runtime
# Usage: ./deploy.sh
set -e

# Configuration
RUNTIME_ID="${RUNTIME_ID:-it_ops_agent_v2-Od8Y3L7coD}"
ROLE_ARN="${ROLE_ARN:-arn:aws:iam::114805761158:role/event-agent-role}"
ECR_REPO="${ECR_REPO:-bedrock-agentcore-it_ops_agent}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-114805761158}"
REGION="${AWS_REGION:-us-east-1}"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "=== IT Ops Agent Deployment (Container) ==="
echo "Runtime:  $RUNTIME_ID"
echo "ECR:      $ECR_URI/$ECR_REPO"
echo "Region:   $REGION"
echo ""

# Step 1: ECR Login
echo "[1/5] Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_URI"

# Step 2: Build ARM64 image
echo "[2/5] Building ARM64 Docker image..."
cd agent/
docker build --platform linux/arm64 -t "${ECR_REPO}:latest" .
docker tag "${ECR_REPO}:latest" "${ECR_URI}/${ECR_REPO}:latest"
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
docker tag "${ECR_REPO}:latest" "${ECR_URI}/${ECR_REPO}:${IMAGE_TAG}"
cd ..
echo "       Tagged: ${IMAGE_TAG} + latest"

# Step 3: Push to ECR
echo "[3/5] Pushing to ECR..."
docker push "${ECR_URI}/${ECR_REPO}:latest"
docker push "${ECR_URI}/${ECR_REPO}:${IMAGE_TAG}"
echo "       Pushed successfully"

# Step 4: Update AgentCore Runtime
echo "[4/5] Updating AgentCore Runtime..."
FULL_IMAGE_URI="${ECR_URI}/${ECR_REPO}:latest"

cat > /tmp/update-runtime.json << EOF
{
    "agentRuntimeId": "${RUNTIME_ID}",
    "agentRuntimeArtifact": {
        "containerConfiguration": {
            "containerUri": "${FULL_IMAGE_URI}"
        }
    },
    "roleArn": "${ROLE_ARN}",
    "networkConfiguration": {
        "networkMode": "PUBLIC"
    }
}
EOF

aws bedrock-agentcore-control update-agent-runtime \
    --cli-input-json file:///tmp/update-runtime.json \
    --region "$REGION"
echo "       Runtime update initiated"

# Step 5: Wait for READY
echo "[5/5] Waiting for runtime to be READY..."
for i in $(seq 1 30); do
    STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "$RUNTIME_ID" \
        --query 'status' --output text \
        --region "$REGION" 2>/dev/null || echo "CHECKING")
    echo "       Attempt $i: $STATUS"
    if [ "$STATUS" = "READY" ]; then
        break
    fi
    sleep 10
done

# Show final state
echo ""
echo "=== Deployment Complete ==="
VERSION=$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "$RUNTIME_ID" \
    --query 'agentRuntimeVersion' --output text \
    --region "$REGION" 2>/dev/null || echo "unknown")
echo "Runtime: $RUNTIME_ID"
echo "Version: $VERSION"
echo "Status:  $STATUS"
echo "Image:   $FULL_IMAGE_URI"
echo ""
echo "Test with:"
echo "  ./tests/test-scenarios.sh 1"

# Cleanup
rm -f /tmp/update-runtime.json
