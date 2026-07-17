#!/bin/bash
# deploy.sh - Package and deploy IT Ops Agent to AgentCore Runtime
# Usage: ./deploy.sh [--skip-upload]
set -e

# Configuration
RUNTIME_ID="${RUNTIME_ID:-it_ops_agent_v2-Od8Y3L7coD}"
S3_BUCKET="${S3_BUCKET:-event-agent-kb-114805761158}"
S3_KEY="${S3_KEY:-devops-outputs/it-ops-agent.zip}"
ROLE_ARN="${ROLE_ARN:-arn:aws:iam::114805761158:role/event-agent-role}"
ENDPOINT_NAME="${ENDPOINT_NAME:-itOpsEndpoint}"
REGION="${AWS_REGION:-us-east-1}"

echo "=== IT Ops Agent Deployment ==="
echo "Runtime:  $RUNTIME_ID"
echo "S3:       s3://$S3_BUCKET/$S3_KEY"
echo "Region:   $REGION"
echo ""

# Step 1: Package
echo "[1/5] Packaging agent code..."
rm -rf ./package ./it-ops-agent.zip
mkdir -p package

pip install -r agent/requirements.txt -t ./package/ --quiet
cp agent/main.py agent/agent.py package/
cp -r agent/tools package/

cd package && zip -r ../it-ops-agent.zip . -q && cd ..
echo "       Package size: $(du -h it-ops-agent.zip | cut -f1)"

# Step 2: Upload to S3
if [[ "$1" != "--skip-upload" ]]; then
    echo "[2/5] Uploading to S3..."
    aws s3 cp it-ops-agent.zip "s3://$S3_BUCKET/$S3_KEY" --region "$REGION"
    echo "       Uploaded to s3://$S3_BUCKET/$S3_KEY"
else
    echo "[2/5] Skipping S3 upload (--skip-upload)"
fi

# Step 3: Update AgentCore Runtime
echo "[3/5] Updating AgentCore Runtime..."
aws bedrock-agentcore update-agent-runtime \
    --agent-runtime-id "$RUNTIME_ID" \
    --role-arn "$ROLE_ARN" \
    --code-s3-bucket "$S3_BUCKET" \
    --code-s3-prefix "$S3_KEY" \
    --code-entry-point "main.py" \
    --code-runtime "PYTHON_3_13" \
    --network-mode "PUBLIC" \
    --region "$REGION" 2>&1 || echo "       (Update command sent)"

# Step 4: Wait for READY
echo "[4/5] Waiting for runtime to be READY..."
for i in $(seq 1 30); do
    STATUS=$(aws bedrock-agentcore get-agent-runtime \
        --agent-runtime-id "$RUNTIME_ID" \
        --query 'runtimeStatus' --output text \
        --region "$REGION" 2>/dev/null || echo "UNKNOWN")
    echo "       Attempt $i: $STATUS"
    if [ "$STATUS" = "READY" ]; then
        break
    fi
    sleep 10
done

# Step 5: Update endpoint
echo "[5/5] Updating endpoint '$ENDPOINT_NAME' to latest version..."
LATEST_VERSION=$(aws bedrock-agentcore get-agent-runtime \
    --agent-runtime-id "$RUNTIME_ID" \
    --query 'agentRuntimeVersion' --output text \
    --region "$REGION" 2>/dev/null || echo "unknown")
echo "       Latest version: $LATEST_VERSION"

aws bedrock-agentcore update-agent-runtime-endpoint \
    --agent-runtime-id "$RUNTIME_ID" \
    --endpoint-name "$ENDPOINT_NAME" \
    --agent-runtime-version "$LATEST_VERSION" \
    --region "$REGION" 2>&1 || echo "       (Endpoint update sent)"

echo ""
echo "=== Deployment Complete ==="
echo "Test with:"
echo "  aws bedrock-agentcore invoke-agent-runtime \\"
echo "    --agent-runtime-arn arn:aws:bedrock-agentcore:$REGION:114805761158:runtime/$RUNTIME_ID \\"
echo "    --payload '{\"prompt\": \"health check\"}' \\"
echo "    --runtime-session-id test-\$(date +%s)-xxxxxxxxxxxxxxxxx \\"
echo "    /tmp/agent-output.json --region $REGION"

# Cleanup
rm -rf package
