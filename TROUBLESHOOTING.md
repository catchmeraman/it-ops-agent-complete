# Troubleshooting Guide — IT Ops Agent Deployment

Every error encountered during deployment, with root cause and fix.

---

## Error 1: Wrong CLI Service Name (exit code 252)

**When:** CodeBuild POST_BUILD phase  
**Command that failed:**
```bash
aws bedrock-agentcore update-agent-runtime --agent-runtime-id it_ops_agent_v2-Od8Y3L7coD ...
```

**Error message:**
```
aws: [ERROR]: argument operation: Found invalid choice 'update-agent-runtime'
```

**Root Cause:**  
AWS has TWO services for AgentCore:
- `bedrock-agentcore` — **Data plane** (invoke agents, manage sessions, memory)
- `bedrock-agentcore-control` — **Control plane** (create/update/delete runtimes, endpoints)

**Fix:**
```bash
# ✅ Correct service for managing runtimes
aws bedrock-agentcore-control update-agent-runtime ...
aws bedrock-agentcore-control get-agent-runtime ...
aws bedrock-agentcore-control create-agent-runtime-endpoint ...

# ✅ Data plane for invoking
aws bedrock-agentcore invoke-agent-runtime ...
```

---

## Error 2: Cannot Change Artifact Type (ValidationException)

**When:** Tried to switch runtime from container to S3 code deployment  
**Command that failed:**
```bash
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-artifact '{"codeConfiguration":{"code":{"s3":{"bucket":"...","prefix":"..."}}}}'
```

**Error message:**
```
ValidationException: Agent artifact type cannot be updated
```

**Root Cause:**  
The runtime `it_ops_agent_v2-Od8Y3L7coD` was originally created with `containerConfiguration`. Once set, you cannot switch between container and code deployment.

**Fix:**  
Keep using containers. Build Docker images and push to ECR instead of S3 zip files.

**Verification:**
```bash
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id it_ops_agent_v2-Od8Y3L7coD \
  --query 'agentRuntimeArtifact' --output json
# Shows: {"containerConfiguration": {"containerUri": "..."}}
```

---

## Error 3: Docker Hub Rate Limiting (429 Too Many Requests)

**When:** CodeBuild BUILD phase — `docker build`  
**Dockerfile line:** `FROM python:3.13-slim`

**Error message:**
```
#2 ERROR: unexpected status from HEAD request to https://registry-1.docker.io/v2/library/python/manifests/3.13-slim: 429 Too Many Requests
```

**Root Cause:**  
Docker Hub limits anonymous pulls to 100 per 6 hours per IP. CodeBuild shares IPs across customers.

**Fix:**  
Use ECR Public Gallery (Amazon-hosted mirror, no rate limits):
```dockerfile
# ❌ Gets rate limited
FROM python:3.13-slim

# ✅ No rate limits, same image
FROM public.ecr.aws/docker/library/python:3.13-slim
```

**Alternative fix:** Authenticate to Docker Hub in pre_build:
```yaml
pre_build:
  commands:
    - echo $DOCKERHUB_TOKEN | docker login --username $DOCKERHUB_USER --password-stdin
```

---

## Error 4: Architecture Mismatch (ARM64 Required)

**When:** `update-agent-runtime` call after successful image push  
**Command that failed:**
```bash
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-artifact '{"containerConfiguration":{"containerUri":"...bedrock-agentcore-it_ops_agent:20260717-165734"}}'
```

**Error message:**
```
ValidationException: Architecture incompatible for uri '...'. Supported platforms: [arm64]
```

**Root Cause:**  
AgentCore Runtime runs on AWS Graviton (ARM64). Default CodeBuild uses x86_64 images.

**Fix:**  
Switch CodeBuild to ARM compute:
```bash
aws codebuild update-project --name it-ops-agent-build \
  --environment '{
    "type": "ARM_CONTAINER",
    "computeType": "BUILD_GENERAL1_SMALL",
    "image": "aws/codebuild/amazonlinux-aarch64-standard:3.0",
    "privilegedMode": true
  }'
```

**Key difference:** `type` must be `ARM_CONTAINER` (not `LINUX_CONTAINER`).

---

## Error 5: IAM PassRole Denied

**When:** CodeBuild POST_BUILD — `update-agent-runtime`  
**Command that failed:**
```bash
aws bedrock-agentcore-control update-agent-runtime --cli-input-json file:///tmp/update.json
```

**Error message:**
```
AccessDeniedException: User: arn:aws:sts::114805761158:assumed-role/it-ops-agent-codebuild-role/AWSCodeBuild-...
is not authorized to perform: iam:PassRole on resource: arn:aws:iam::114805761158:role/event-agent-role
because no identity-based policy allows the iam:PassRole action
```

**Root Cause:**  
When you call `update-agent-runtime` with a `roleArn`, AWS requires that the caller has permission to pass that role. The CloudFormation template had PassRole for `it-ops-agent-runtime-role` but the actual runtime uses `event-agent-role`.

**Fix:**
```bash
aws iam put-role-policy \
  --role-name it-ops-agent-codebuild-role \
  --policy-name PassEventAgentRole \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::114805761158:role/event-agent-role"
    }]
  }'
```

---

## Error 6: YAML Parsing Error in buildspec.yml

**When:** CodeBuild DOWNLOAD_SOURCE phase  
**Error message:**
```
Expected Commands[4] to be of string type: found subkeys instead at line 41,
value of the key tag on line 40 might be empty
```

**Root Cause:**  
Multi-line YAML `|` blocks combined with shell variable expansion and nested quotes confuse the YAML parser.

**Fix:**  
Keep all commands on single lines. For complex JSON payloads, use `printf` to write a file:

```yaml
# ❌ Multi-line with complex escaping — YAML parser chokes
- |
  aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-artifact '{"containerConfiguration":{"containerUri":"${IMAGE}"}}'

# ✅ Write JSON to file, then reference it
- printf '{"agentRuntimeId":"%s","agentRuntimeArtifact":{"containerConfiguration":{"containerUri":"%s"}},"roleArn":"%s","networkConfiguration":{"networkMode":"PUBLIC"}}' "$RUNTIME_ID" "$IMAGE_URI" "$ROLE_ARN" > /tmp/update.json
- aws bedrock-agentcore-control update-agent-runtime --cli-input-json file:///tmp/update.json
```

---

## Error 7: Environment Variables Not Persisting Across Phases

**When:** `IMAGE_TAG` set in `pre_build` is empty in `build` phase  

**Root Cause:**  
Each CodeBuild phase runs in a new shell context. `export` in one phase doesn't carry to the next.

**Fix options:**
1. Set the variable in the same phase where it's used
2. Write to a file and source it
3. Compute the value fresh when needed

```yaml
# ✅ Compute fresh in post_build
post_build:
  commands:
    - export LATEST_TAG=$(aws ecr describe-images --repository-name $ECR_REPO --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text)
```

---

## Error 8: Git Push 403 Forbidden to CodeCommit

**When:** Pushing from local terminal to CodeCommit  
**Error message:**
```
fatal: unable to access 'https://git-codecommit.us-east-1.amazonaws.com/...': The requested URL returned error: 403
```

**Root Cause:**  
VS Code's git credential helper socket (`/var/folders/.../vscode-git-xxx.sock`) interferes with the AWS credential helper.

**Fix:**  
Use the CodeCommit API directly instead of git push:
```bash
aws codecommit create-commit \
  --repository-name it-ops-agent \
  --branch-name main \
  --parent-commit-id $(aws codecommit get-branch --repository-name it-ops-agent --branch-name main --query 'branch.commitId' --output text) \
  --commit-message "your commit message" \
  --put-files "filePath=buildspec.yml,fileContent=$(base64 < buildspec.yml)"
```

Or configure git without VS Code interference:
```bash
unset GIT_ASKPASS SSH_ASKPASS
git -c credential.helper='!aws codecommit credential-helper $@' -c credential.UseHttpPath=true push origin main
```

---

## Error 9: `runtimeSessionId` Too Short

**When:** Invoking the agent runtime for testing  
**Error message:**
```
Parameter validation failed: Invalid length for parameter runtimeSessionId, value: 15, valid min length: 33
```

**Fix:** Session IDs must be at least 33 characters:
```bash
# ❌ Too short
--runtime-session-id "test-123"

# ✅ Long enough (use timestamp + random)
--runtime-session-id "test-$(date +%s)-$(openssl rand -hex 8)"
```

---

## Pipeline Recovery: How to Retry

After fixing an error, you don't need to push new code. Retry the failed stage:

```bash
aws codepipeline retry-stage-execution \
  --pipeline-name it-ops-agent-pipeline \
  --stage-name Build-Test-Deploy \
  --pipeline-execution-id $(aws codepipeline get-pipeline-state --name it-ops-agent-pipeline --query 'stageStates[1].latestExecution.pipelineExecutionId' --output text) \
  --retry-mode FAILED_ACTIONS \
  --region us-east-1
```

---

## Validation Commands

After deployment, verify everything is healthy:

```bash
# Runtime status
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id it_ops_agent_v2-Od8Y3L7coD \
  --query '{status:status,version:agentRuntimeVersion,image:agentRuntimeArtifact.containerConfiguration.containerUri}' \
  --output table --region us-east-1

# Pipeline status
aws codepipeline get-pipeline-state --name it-ops-agent-pipeline \
  --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
  --output table --region us-east-1

# Latest ECR image
aws ecr describe-images --repository-name bedrock-agentcore-it_ops_agent \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].{tags:imageTags,pushed:imagePushedAt}' \
  --output json --region us-east-1
```
