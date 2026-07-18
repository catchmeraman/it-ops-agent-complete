# How I Built (and Actually Deployed) an IT Operations Agent on Amazon Bedrock AgentCore

> **Level**: 300 (Advanced) | **Time**: 3-4 hours | **Region**: us-east-1  
> **Services**: Amazon Bedrock AgentCore Runtime, ECR, CodePipeline, CodeBuild, CodeCommit, EventBridge, SNS, CloudWatch, SSM, EC2  
> **Runtime**: it_ops_agent_v2-Od8Y3L7coD | **Account**: 114805761158  
> **Final Version**: v8 (deployed 2026-07-17)

---

## What This Blog Covers

This isn't a "hello world" agent tutorial. This is a production deployment with:
- Real agent code (12 tools, Strands framework, Claude Sonnet)
- Real CI/CD (CodeCommit → CodeBuild → ECR → AgentCore auto-update)
- Real errors I hit and exactly how I fixed each one
- Real AWS Console URLs so you can see what was built

If you want to skip the story and just deploy: jump to [Quick Start](#quick-start).

---

## The Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    IT Ops Agent - Production Architecture             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────┐     ┌─────────────────────────────────────┐       │
│  │  Operator /  │     │   Amazon Bedrock AgentCore Runtime   │       │
│  │  CloudWatch  │────▶│   it_ops_agent_v2 (v8 - READY)      │       │
│  │  Alarm       │     │   ARM64 Container on Firecracker     │       │
│  └──────────────┘     └──────────┬───────────────────────────┘       │
│                                   │                                   │
│         ┌─────────────────────────┼─────────────────────────┐        │
│         │                         ▼                          │        │
│         │  CloudWatch  CloudTrail  SSM   EC2   SNS   KB     │        │
│         │  (diagnose)  (changes)  (fix) (mgmt) (alert)(sop) │        │
│         └────────────────────────────────────────────────────┘        │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │  CI/CD Pipeline (auto-triggers on git push to main)           │   │
│  │                                                                │   │
│  │  CodeCommit → EventBridge → CodePipeline → CodeBuild (ARM64) │   │
│  │       → ECR Push → bedrock-agentcore-control update → READY  │   │
│  └───────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## What the Agent Can Do

| Tool | Category | What It Does |
|------|----------|--------------|
| `get_alarms` | Diagnose | List CloudWatch alarms by state (ALARM/OK/ALL) |
| `get_metric_statistics` | Diagnose | Get metric data for any namespace/metric/dimension |
| `list_metrics` | Diagnose | Discover available CloudWatch metrics |
| `search_logs` | Diagnose | Filter CloudWatch Logs with patterns |
| `get_recent_errors` | Diagnose | Find ERROR/EXCEPTION/FATAL in logs |
| `lookup_recent_changes` | Diagnose | CloudTrail events for recent infra changes |
| `run_command` | Remediate | Execute shell commands via SSM Run Command |
| `get_command_status` | Remediate | Check SSM command output |
| `describe_instances` | Remediate | List EC2 instances with details |
| `manage_instance` | Remediate | Start/stop/reboot EC2 instances |
| `send_notification` | Alert | Publish to SNS topic |
| `query_runbook` | Learn | Query Bedrock Knowledge Base for SOPs |

---

## Quick Start

### Option 1: Deploy Everything (CloudFormation)

```bash
git clone https://github.com/catchmeraman/it-ops-agent-complete.git
cd it-ops-agent-complete

# Deploy CI/CD infrastructure
aws cloudformation deploy \
  --template-file infrastructure/cloudformation/template.yaml \
  --stack-name it-ops-agent-infra \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Build & push container manually (first time)
./scripts/deploy.sh
```

### Option 2: Terraform

```bash
cd infrastructure/terraform
terraform init
terraform apply
```

---

## Step-by-Step Implementation

### Step 1: The IAM Role

The AgentCore Runtime needs an execution role. My existing role `event-agent-role` (created 2026-03-23) has:

**Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": ["bedrock-agentcore.amazonaws.com", "bedrock.amazonaws.com", "ec2.amazonaws.com"]
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::114805761158:root"},
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Inline Policies (10 total):**
- `ITOpsAgentAccess` — Bedrock model invocation + Knowledge Base
- `DevOpsAgentsAccess` — CloudWatch, CloudTrail, SSM, EC2
- `EventAgentIdentityPolicy` — AgentCore workload identity
- `S3DeployAccess` — Read artifacts from S3
- `EKSAccess` — EKS cluster read
- `ECRAccess` — Pull container images
- Plus: `AgentPolicy`, `AwsMcpAccess`, `DevOpsAgentsS3Output`, `SecretsManagerGatewaySecret`

**Attached Managed Policies:**
- `AmazonSSMManagedInstanceCore`
- `ReadOnlyAccess`

> 📸 **Screenshot 4** — IAM Permissions: https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/event-agent-role?section=permissions
> 📸 **Screenshot 5** — Trust Policy: https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/event-agent-role?section=trust

---

### Step 2: Agent Code

The agent runs as an HTTP server on port 8080 inside a container. AgentCore routes requests to it.

**Key files:**
- `main.py` — HTTP server (POST = invoke agent, GET = health check)
- `agent.py` — Creates Strands Agent with Claude Sonnet + 12 tools
- `tools/*.py` — Each tool is a `@tool` decorated function returning a dict

**Critical design decisions:**
- Tools return structured dicts, not raw AWS responses
- Each tool handles its own errors gracefully
- System prompt enforces "diagnose before remediate" pattern
- Environment variables for SNS topic ARN and KB ID

---

### Step 3: Container Build (ARM64 Required!)

**This is where most people will get stuck.** AgentCore Runtime uses ARM64 (Graviton). Your Docker image MUST be arm64.

**Dockerfile:**
```dockerfile
FROM public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py agent.py ./
COPY tools/ ./tools/
EXPOSE 8080
CMD ["python", "main.py"]
```

**Why `public.ecr.aws` instead of Docker Hub?**  
CodeBuild gets rate-limited by Docker Hub (`429 Too Many Requests`). ECR Public Gallery has no such limits.

**ECR Repository:** `bedrock-agentcore-it_ops_agent`  
**Image:** `114805761158.dkr.ecr.us-east-1.amazonaws.com/bedrock-agentcore-it_ops_agent:latest`

---

### Step 4: AgentCore Runtime

The runtime was created on 2026-03-31 and has been updated through 8 versions:

| Version | Date | Change |
|---------|------|--------|
| v1-v6 | Mar 31 | Initial development iterations |
| v7 | Jul 17 | First deployment from new CI/CD pipeline |
| v8 | Jul 17 | Pipeline auto-deployed (fully automated) |

**Runtime Configuration:**
- Network Mode: PUBLIC (IAM-secured)
- Idle Timeout: 900 seconds (15 min)
- Max Lifetime: 28800 seconds (8 hours)
- Endpoints: `DEFAULT` + `itOpsEndpoint`

> 📸 **Screenshot 1** — Runtime Dashboard: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes
> 📸 **Screenshot 2** — Configuration: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD
> 📸 **Screenshot 3** — Endpoints: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/endpoints
> 📸 **Screenshot 6** — Versions: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/versions

---

### Step 5: CI/CD Pipeline

Deployed via CloudFormation stack `it-ops-agent-infra`:

```bash
aws cloudformation deploy \
  --template-file infrastructure/cloudformation/template.yaml \
  --stack-name it-ops-agent-infra \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

**What it creates:**

| Resource | Name | Purpose |
|----------|------|---------|
| CodeCommit | `it-ops-agent` | Source repo |
| CodeBuild | `it-ops-agent-build` | ARM64 Docker build + deploy |
| CodePipeline | `it-ops-agent-pipeline` | Orchestrates Source → Build |
| EventBridge | `it-ops-agent-code-change` | Auto-triggers on push to main |
| SNS | `it-ops-agent-alerts` | Agent notification channel |
| IAM × 4 | Various | Roles for each service |

**The buildspec.yml (what CodeBuild actually does):**
```yaml
phases:
  pre_build:
    commands:
      - aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_URI
  build:
    commands:
      - docker build -t $ECR_REPO:latest .    # ARM64 native (CodeBuild ARM)
      - docker push $ECR_URI/$ECR_REPO:latest
  post_build:
    commands:
      - # Write JSON to file (avoids shell escaping nightmares)
      - printf '{"agentRuntimeId":"%s",...}' > /tmp/update.json
      - aws bedrock-agentcore-control update-agent-runtime --cli-input-json file:///tmp/update.json
      - # Wait for READY
      - aws bedrock-agentcore-control get-agent-runtime --query status
```

> 📸 **Screenshot 8** — Pipeline: https://us-east-1.console.aws.amazon.com/codesuite/codepipeline/pipelines/it-ops-agent-pipeline/view?region=us-east-1
> 📸 **Screenshot 9** — CodeBuild: https://us-east-1.console.aws.amazon.com/codesuite/codebuild/projects/it-ops-agent-build/history?region=us-east-1
> 📸 **Screenshot 10** — EventBridge: https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/rules/it-ops-agent-code-change

---

### Step 6: Deployment Flow (Day-to-Day)

```bash
# Make a code change
vim tools/ssm_tools.py

# Push (pipeline auto-triggers via EventBridge)
git add . && git commit -m "feat: add disk cleanup" && git push

# Pipeline does everything:
# 1. Pulls source from CodeCommit
# 2. Builds ARM64 Docker image
# 3. Pushes to ECR
# 4. Calls bedrock-agentcore-control update-agent-runtime
# 5. Runtime goes UPDATING → READY (new version)
```

---

## Troubleshooting: Every Error I Hit

### Error 1: `aws bedrock-agentcore update-agent-runtime` — exit code 252

**Symptom:** Build fails in POST_BUILD phase  
**Root Cause:** Wrong CLI service name  
**Fix:** Use `bedrock-agentcore-control` (control plane), not `bedrock-agentcore` (data plane)

```bash
# ❌ Wrong
aws bedrock-agentcore update-agent-runtime ...

# ✅ Correct
aws bedrock-agentcore-control update-agent-runtime ...
```

---

### Error 2: `Agent artifact type cannot be updated`

**Symptom:** Tried to switch from container to S3 code deployment  
**Root Cause:** Once a runtime is created with a container artifact, it cannot be changed to code  
**Fix:** Keep using containers. Build Docker images and push to ECR.

---

### Error 3: `429 Too Many Requests` from Docker Hub

**Symptom:** `docker build` fails pulling `python:3.13-slim`  
**Root Cause:** Docker Hub rate limits anonymous pulls (100/6hr for anonymous, 200/6hr for authenticated)  
**Fix:** Use ECR Public Gallery base images:

```dockerfile
# ❌ Rate limited
FROM python:3.13-slim

# ✅ No rate limits
FROM public.ecr.aws/docker/library/python:3.13-slim
```

---

### Error 4: `Architecture incompatible... Supported platforms: [arm64]`

**Symptom:** `update-agent-runtime` rejects the image  
**Root Cause:** CodeBuild default environment is x86_64. AgentCore requires ARM64.  
**Fix:** Switch CodeBuild to ARM environment:

```bash
aws codebuild update-project --name it-ops-agent-build \
  --environment '{"type":"ARM_CONTAINER","computeType":"BUILD_GENERAL1_SMALL","image":"aws/codebuild/amazonlinux-aarch64-standard:3.0","privilegedMode":true,...}'
```

---

### Error 5: `AccessDeniedException: iam:PassRole`

**Symptom:** CodeBuild can build + push but can't update the runtime  
**Root Cause:** `update-agent-runtime` requires `iam:PassRole` for the runtime's execution role  
**Fix:** Add PassRole permission to CodeBuild's IAM role:

```bash
aws iam put-role-policy --role-name it-ops-agent-codebuild-role \
  --policy-name PassEventAgentRole \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"iam:PassRole","Resource":"arn:aws:iam::114805761158:role/event-agent-role"}]}'
```

---

### Error 6: YAML buildspec parsing errors

**Symptom:** `Expected Commands[4] to be of string type: found subkeys instead`  
**Root Cause:** Multi-line `|` blocks in YAML with complex shell escaping  
**Fix:** Keep all commands on single lines. For complex JSON, write to a file:

```yaml
# ❌ Breaks YAML parser
- |
  aws bedrock-agentcore-control update-agent-runtime \
    --agent-runtime-artifact '{"containerConfiguration":...}'

# ✅ Works
- printf '{"agentRuntimeId":"%s",...}' "$ID" > /tmp/update.json
- aws bedrock-agentcore-control update-agent-runtime --cli-input-json file:///tmp/update.json
```

---

### Error 7: Environment variables lost between CodeBuild phases

**Symptom:** `IMAGE_TAG` set in `pre_build` is empty in `build`  
**Root Cause:** Each CodeBuild phase runs in a separate shell context. `export` doesn't persist.  
**Fix:** Either set the variable in the same phase where it's used, or compute it fresh:

```yaml
# ✅ Compute in the phase where needed
post_build:
  commands:
    - export IMAGE_TAG=$(aws ecr describe-images --query 'sort_by(...)[-1].imageTags[0]' --output text)
```

---

### Error 8: Git push to CodeCommit — 403 Forbidden

**Symptom:** `fatal: Authentication failed`  
**Root Cause:** VS Code git credential socket interference  
**Fix:** Use the CodeCommit API directly:

```bash
aws codecommit create-commit \
  --repository-name it-ops-agent \
  --branch-name main \
  --parent-commit-id $(aws codecommit get-branch --repository-name it-ops-agent --branch-name main --query 'branch.commitId' --output text) \
  --put-files "filePath=buildspec.yml,fileContent=$(base64 < buildspec.yml)"
```

---

## 12 Test Scenarios

Run these after deployment to validate the agent:

```bash
# Quick test
./tests/test-scenarios.sh 1   # Health check
./tests/test-scenarios.sh 2   # CloudWatch alarms
./tests/test-scenarios.sh 4   # List EC2 instances
./tests/test-scenarios.sh 12  # Full incident response (multi-tool)
```

| # | Test | What It Validates |
|---|------|-------------------|
| 1 | Health check | Agent responds, lists capabilities |
| 2 | CloudWatch alarms | `get_alarms` tool works |
| 3 | CPU metrics | `get_metric_statistics` tool works |
| 4 | Describe instances | `describe_instances` tool works |
| 5 | Log search | `search_logs` tool works |
| 6 | CloudTrail changes | `lookup_recent_changes` tool works |
| 7 | Full CPU diagnosis | Multi-tool workflow (alarms → metrics → trail) |
| 8 | SSM disk check | `run_command` with `df -h` |
| 9 | SSM top processes | `run_command` with `ps aux` |
| 10 | SNS notification | `send_notification` tool works |
| 11 | Knowledge Base | `query_runbook` tool works |
| 12 | Full incident RCA | All tools combined |

---

## Screenshot Capture Guide (Direct Links)

### Already Deployed — Capture NOW:

| # | What | Direct URL |
|---|------|-----------|
| 1 | AgentCore Runtime Dashboard | https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes |
| 2 | Runtime Configuration | https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD |
| 3 | Endpoints (DEFAULT + itOpsEndpoint) | https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/endpoints |
| 4 | IAM Role Permissions | https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/event-agent-role?section=permissions |
| 5 | IAM Trust Relationships | https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/event-agent-role?section=trust |
| 6 | Version History (v1-v8) | https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/versions |
| 7 | itOpsEndpoint Details | https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/endpoints |
| 8 | CodePipeline (green) | https://us-east-1.console.aws.amazon.com/codesuite/codepipeline/pipelines/it-ops-agent-pipeline/view?region=us-east-1 |
| 9 | CodeBuild History | https://us-east-1.console.aws.amazon.com/codesuite/codebuild/projects/it-ops-agent-build/history?region=us-east-1 |
| 10 | EventBridge Rule | https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/rules/it-ops-agent-code-change |
| 11 | S3 Artifact | https://s3.console.aws.amazon.com/s3/buckets/event-agent-kb-114805761158?region=us-east-1&prefix=devops-outputs/ |
| 12 | Knowledge Base | https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/knowledge-bases/84C8RSCN6O |
| 13 | ECR Repository | https://us-east-1.console.aws.amazon.com/ecr/repositories/private/114805761158/bedrock-agentcore-it_ops_agent?region=us-east-1 |
| 14 | CloudFormation Stack | https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/stackinfo?filteringText=it-ops-agent-infra |
| 15 | CodeCommit Repo | https://us-east-1.console.aws.amazon.com/codesuite/codecommit/repositories/it-ops-agent/browse?region=us-east-1 |
| 16 | SNS Topic | https://us-east-1.console.aws.amazon.com/sns/v3/home?region=us-east-1#/topic/arn:aws:sns:us-east-1:114805761158:it-ops-agent-alerts |

---

## Cost

| Component | Monthly Cost |
|-----------|-------------|
| AgentCore Runtime | Session-based (no idle cost) |
| Claude Sonnet | ~$3/1M input, ~$15/1M output tokens |
| ECR Storage | ~$0.10/GB/month (image ~120MB) |
| CodeBuild | ~$5 (10 builds × 3 min ARM) |
| CodePipeline | $1/pipeline/month |
| Everything else | < $2 |
| **Total (light usage)** | **~$10-15/month** |

---

## Live Test Results (2026-07-18)

We ran 5 end-to-end tests against the production agent. All 4 core capabilities work:

| # | Test | Result | Latency | Agent Action |
|---|------|--------|---------|-------------|
| 1 | Health Check | ✅ | 4.5s | Found 2 instances — 1 stopped, 1 healthy |
| 2 | Start Instance | ✅ | 6.3s | Started i-014a2a43c1525083a, verified pending |
| 3 | SSM App Check | ✅ | 4.8s | Confirmed App Server healthy via SSM |
| 4 | SNS Notification | ✅ | 4.0s | Sent status report (MessageId: 23b0989b) |
| 5 | Full Maintenance | ❌ | 0.5s | Model access issue (Legacy model) |

### Example: Full Diagnostic → Remediate → Notify Flow

```
Operator: "Run a health check on all known instances."
Agent:    → Calls health_check(i-014a2a43c1525083a) → STOPPED
          → Calls health_check(i-051e86cc20c88aa4a) → Running, OK
          → "Test Server is stopped. App Server is healthy."

Operator: "Start the test server."
Agent:    → Calls server_start(i-014a2a43c1525083a) → Success
          → Calls health_check(i-014a2a43c1525083a) → Pending
          → "Started. Check back in 30-60s for full health."

Operator: "Send notification about this to the ops team."
Agent:    → Calls send_notification(subject, message)
          → "✅ Sent! MessageId: 23b0989b..."
```

### Observability Logs (CloudWatch)

Every invocation is automatically logged with structured JSON:

```json
{
  "timestamp": "2026-07-18T08:55:01.937Z",
  "level": "INFO",
  "message": "Invocation completed successfully (6.362s)",
  "logger": "bedrock_agentcore.app",
  "requestId": "9a9c45ac-0fad-4738-be96-2e1c4b044fe0",
  "sessionId": "test-start-1784364889-d17ed90886c83182"
}
```

**Log group**: `/aws/bedrock-agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD-itOpsEndpoint`

📸 **Screenshot 17**: https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Faws$252Fbedrock-agentcore$252Fruntimes$252Fit_ops_agent_v2-Od8Y3L7coD-itOpsEndpoint

> Full test details with stack traces, performance analysis, and reproduction commands: [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md)

---

## What I'd Do Differently Next Time

1. **Start with ARM from day one** — would have saved 2 failed builds
2. **Use `--cli-input-json file://`** for any CLI command with complex JSON arguments
3. **Test the credential flow locally first** — CodeBuild IAM issues are painful to debug
4. **Use `bedrock-agentcore-control` for management** — the data plane (`bedrock-agentcore`) is for invocations only

---

## Resources

- [Amazon Bedrock AgentCore Docs](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/)
- [Strands Agents Framework](https://github.com/strands-agents/strands-agents)
- [Source Code (GitHub)](https://github.com/catchmeraman/it-ops-agent-complete)
- [CloudFormation Template](infrastructure/cloudformation/template.yaml)
- [Terraform Config](infrastructure/terraform/)

---

*Deployed 2026-07-17 | Runtime v8 | Pipeline: all green ✅*
