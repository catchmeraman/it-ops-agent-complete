#!/bin/bash
# setup-infrastructure.sh - Deploy all infrastructure via CloudFormation
# Run this ONCE to create CodeCommit, CodeBuild, CodePipeline, EventBridge, SNS
set -e

STACK_NAME="it-ops-agent-infra"
TEMPLATE="infrastructure/cloudformation/template.yaml"
REGION="${AWS_REGION:-us-east-1}"
NOTIFICATION_EMAIL="${1:-ops-team@example.com}"

echo "=== Deploying IT Ops Agent Infrastructure ==="
echo "Stack:    $STACK_NAME"
echo "Region:   $REGION"
echo "Email:    $NOTIFICATION_EMAIL"
echo ""

# Validate template
echo "[1/4] Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://$TEMPLATE" \
    --region "$REGION" > /dev/null
echo "       Template valid ✓"

# Deploy stack
echo "[2/4] Deploying stack (this takes 3-5 minutes)..."
aws cloudformation deploy \
    --template-file "$TEMPLATE" \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        NotificationEmail="$NOTIFICATION_EMAIL" \
    --region "$REGION"
echo "       Stack deployed ✓"

# Get outputs
echo "[3/4] Fetching outputs..."
CLONE_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='CodeRepoCloneUrl'].OutputValue" \
    --output text --region "$REGION")

SNS_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='SNSTopicArn'].OutputValue" \
    --output text --region "$REGION")

echo ""
echo "=== Infrastructure Ready ==="
echo ""
echo "CodeCommit clone URL: $CLONE_URL"
echo "SNS Topic ARN:        $SNS_ARN"
echo ""

# Step 4: Push agent code to CodeCommit
echo "[4/4] Pushing agent code to CodeCommit..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git init
git remote add origin "$CLONE_URL"

# Copy agent source files
cp -r "$OLDPWD/agent/"* .
mkdir -p tests
cp -r "$OLDPWD/tests/"* tests/ 2>/dev/null || true

git add .
git commit -m "Initial IT Ops Agent deployment"
git push origin main 2>/dev/null || git push --set-upstream origin main

cd "$OLDPWD"
rm -rf "$TEMP_DIR"

echo ""
echo "=== Done! Pipeline will automatically trigger ==="
echo ""
echo "Monitor pipeline:  https://$REGION.console.aws.amazon.com/codesuite/codepipeline/pipelines/it-ops-agent-pipeline/view?region=$REGION"
echo "Confirm SNS email: Check $NOTIFICATION_EMAIL inbox"
