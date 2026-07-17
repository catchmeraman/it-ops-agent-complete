# CI/CD Pipeline — Complete Documentation

## Overview

The IT Ops Agent uses a fully automated CI/CD pipeline that deploys new agent code on every git push. No manual steps required after initial setup.

---

## Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                         CI/CD Pipeline End-to-End Flow                             │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                    │
│  Developer                                                                         │
│     │                                                                              │
│     │ git push main                                                                │
│     ▼                                                                              │
│  ┌─────────────┐    EventBridge    ┌──────────────┐    Trigger    ┌────────────┐  │
│  │ CodeCommit  │───────Rule───────▶│  EventBridge │──────────────▶│CodePipeline│  │
│  │ it-ops-agent│    detects push   │  Rule        │               │            │  │
│  └─────────────┘                   └──────────────┘               └─────┬──────┘  │
│                                                                          │         │
│                                                                          ▼         │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │                    CodeBuild (ARM64 Environment)                            │   │
│  │                                                                             │   │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌─────────────────────┐    │   │
│  │  │ INSTALL  │──▶│PRE_BUILD │──▶│  BUILD   │──▶│     POST_BUILD      │    │   │
│  │  │          │   │          │   │          │   │                      │    │   │
│  │  │ pip      │   │ pytest   │   │ docker   │   │ ECR push            │    │   │
│  │  │ install  │   │ ECR      │   │ build    │   │ agentcore-control   │    │   │
│  │  │ pytest   │   │ login    │   │ (ARM64)  │   │ update-agent-runtime│    │   │
│  │  └──────────┘   └──────────┘   └──────────┘   └──────────┬──────────┘    │   │
│  └─────────────────────────────────────────────────────────────┼──────────────┘   │
│                                                                  │                  │
│                                                                  ▼                  │
│  ┌──────────────┐         ┌──────────────────────────────────────────────────┐    │
│  │     ECR      │◀────────│  Docker Image (ARM64)                            │    │
│  │ bedrock-     │         │  python:3.13 + strands-agents + boto3 + tools    │    │
│  │ agentcore-   │         └──────────────────────────────────────────────────┘    │
│  │ it_ops_agent │                                                                  │
│  └──────┬───────┘                                                                  │
│         │                                                                           │
│         │ bedrock-agentcore-control                                                 │
│         │ update-agent-runtime                                                      │
│         ▼                                                                           │
│  ┌──────────────────────────────────────────────────────────────────────────┐      │
│  │              Amazon Bedrock AgentCore Runtime                             │      │
│  │                                                                           │      │
│  │  Status: UPDATING ──────▶ READY (new version created)                    │      │
│  │  it_ops_agent_v2-Od8Y3L7coD                                              │      │
│  │  Version: v8                                                              │      │
│  │  Image: 114805761158.dkr.ecr.us-east-1.amazonaws.com/                   │      │
│  │         bedrock-agentcore-it_ops_agent:latest                            │      │
│  └──────────────────────────────────────────────────────────────────────────┘      │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. CodeCommit Repository

| Property | Value |
|----------|-------|
| Name | `it-ops-agent` |
| Branch | `main` |
| URL | https://git-codecommit.us-east-1.amazonaws.com/v1/repos/it-ops-agent |
| Console | https://us-east-1.console.aws.amazon.com/codesuite/codecommit/repositories/it-ops-agent/browse?region=us-east-1 |

**Files in repo:**
```
it-ops-agent/
├── main.py              # HTTP server entry point (port 8080)
├── agent.py             # Strands Agent + Claude Sonnet
├── tools/
│   ├── __init__.py
│   ├── cloudwatch_tools.py
│   ├── log_tools.py
│   ├── ssm_tools.py
│   ├── ec2_tools.py
│   ├── cloudtrail_tools.py
│   ├── sns_tools.py
│   └── kb_tools.py
├── requirements.txt     # strands-agents, boto3
├── Dockerfile           # ARM64 container definition
├── buildspec.yml        # CodeBuild instructions
└── tests/
    └── __init__.py
```

---

### 2. EventBridge Rule

| Property | Value |
|----------|-------|
| Name | `it-ops-agent-code-change` |
| State | ENABLED |
| Console | https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/rules/it-ops-agent-code-change |

**Event Pattern:**
```json
{
  "source": ["aws.codecommit"],
  "detail-type": ["CodeCommit Repository State Change"],
  "resources": ["arn:aws:codecommit:us-east-1:114805761158:it-ops-agent"],
  "detail": {
    "event": ["referenceCreated", "referenceUpdated"],
    "referenceName": ["main"]
  }
}
```

**Target:** CodePipeline `it-ops-agent-pipeline`  
**Role:** `it-ops-agent-eventbridge-role` (has `codepipeline:StartPipelineExecution`)

---

### 3. CodePipeline

| Property | Value |
|----------|-------|
| Name | `it-ops-agent-pipeline` |
| Stages | Source → Build-Test-Deploy |
| Artifact Store | S3: `event-agent-kb-114805761158` |
| Console | https://us-east-1.console.aws.amazon.com/codesuite/codepipeline/pipelines/it-ops-agent-pipeline/view?region=us-east-1 |

**Stage 1: Source**
- Provider: CodeCommit
- Repo: `it-ops-agent`
- Branch: `main`
- PollForSourceChanges: false (EventBridge triggers it)
- Output: `SourceOutput`

**Stage 2: Build-Test-Deploy**
- Provider: CodeBuild
- Project: `it-ops-agent-build`
- Input: `SourceOutput`
- Output: `BuildOutput`

---

### 4. CodeBuild Project

| Property | Value |
|----------|-------|
| Name | `it-ops-agent-build` |
| Environment | ARM_CONTAINER |
| Image | `aws/codebuild/amazonlinux-aarch64-standard:3.0` |
| Compute | BUILD_GENERAL1_SMALL |
| Privileged | true (Docker builds) |
| Console | https://us-east-1.console.aws.amazon.com/codesuite/codebuild/projects/it-ops-agent-build/history?region=us-east-1 |

**Environment Variables:**
| Variable | Value |
|----------|-------|
| RUNTIME_ID | `it_ops_agent_v2-Od8Y3L7coD` |
| ROLE_ARN | `arn:aws:iam::114805761158:role/event-agent-role` |
| ECR_REPO | `bedrock-agentcore-it_ops_agent` |
| AWS_ACCOUNT_ID | `114805761158` |

**Build Phases:**

| Phase | Duration | What Happens |
|-------|----------|--------------|
| INSTALL | ~10s | `pip install pytest` |
| PRE_BUILD | ~5s | Run tests, ECR login |
| BUILD | ~90s | Docker build ARM64, tag, push to ECR |
| POST_BUILD | ~90s | Update AgentCore runtime, wait for READY |

**CodeBuild IAM Role:** `it-ops-agent-codebuild-role`

Permissions:
- `logs:*` — CloudWatch Logs for build output
- `s3:GetObject/PutObject` — Pipeline artifacts
- `codecommit:GitPull` — Pull source code
- `ecr:*` — Push Docker images
- `bedrock-agentcore-control:*` — Update runtime
- `iam:PassRole` — Pass `event-agent-role` to runtime

---

### 5. ECR Repository

| Property | Value |
|----------|-------|
| Name | `bedrock-agentcore-it_ops_agent` |
| URI | `114805761158.dkr.ecr.us-east-1.amazonaws.com/bedrock-agentcore-it_ops_agent` |
| Console | https://us-east-1.console.aws.amazon.com/ecr/repositories/private/114805761158/bedrock-agentcore-it_ops_agent?region=us-east-1 |

**Image:**
- Tag: `latest` (overwritten each deploy)
- Architecture: `linux/arm64`
- Size: ~120MB
- Base: `public.ecr.aws/docker/library/python:3.13-slim`

---

### 6. AgentCore Runtime Update

The final step uses the **control plane** API:

```bash
aws bedrock-agentcore-control update-agent-runtime \
  --cli-input-json '{
    "agentRuntimeId": "it_ops_agent_v2-Od8Y3L7coD",
    "agentRuntimeArtifact": {
      "containerConfiguration": {
        "containerUri": "114805761158.dkr.ecr.us-east-1.amazonaws.com/bedrock-agentcore-it_ops_agent:latest"
      }
    },
    "roleArn": "arn:aws:iam::114805761158:role/event-agent-role",
    "networkConfiguration": {"networkMode": "PUBLIC"}
  }'
```

This creates a **new immutable version** (v8, v9, etc.) and transitions the runtime:
```
READY → UPDATING → READY (new version)
```

---

## End-to-End Timeline (Real Execution)

```
T+0:00   Developer pushes to CodeCommit main branch
T+0:02   EventBridge detects referenceUpdated event
T+0:03   CodePipeline execution starts
T+0:05   Source stage pulls code from CodeCommit (Succeeded)
T+0:10   CodeBuild starts (PROVISIONING)
T+0:15   INSTALL phase - pip install
T+0:20   PRE_BUILD - pytest + ECR login
T+0:25   BUILD - docker build (ARM64 native)
T+1:50   BUILD - docker push to ECR
T+2:00   POST_BUILD - bedrock-agentcore-control update-agent-runtime
T+2:05   Runtime status: UPDATING
T+3:00   POST_BUILD - runtime status check: READY
T+3:05   CodeBuild: SUCCEEDED
T+3:10   CodePipeline: All Stages Succeeded ✅
```

**Total time: ~3 minutes** from push to live deployment.

---

## IAM Roles Summary

| Role | Used By | Key Permissions |
|------|---------|-----------------|
| `event-agent-role` | AgentCore Runtime | Bedrock, CloudWatch, SSM, EC2, SNS, S3 |
| `it-ops-agent-codebuild-role` | CodeBuild | ECR, S3, CodeCommit, AgentCore Control, PassRole |
| `it-ops-agent-pipeline-role` | CodePipeline | S3, CodeCommit, CodeBuild |
| `it-ops-agent-eventbridge-role` | EventBridge | `codepipeline:StartPipelineExecution` |

---

## Rollback Procedure

If a new version breaks the agent:

```bash
# Check current version
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id it_ops_agent_v2-Od8Y3L7coD \
  --query '{status:status,version:agentRuntimeVersion}' --output table

# Rollback to previous version (e.g., v7)
aws bedrock-agentcore-control update-agent-runtime-endpoint \
  --agent-runtime-id it_ops_agent_v2-Od8Y3L7coD \
  --name itOpsEndpoint \
  --agent-runtime-version 7
```

---

## Monitoring

**Pipeline failures:** Check CodeBuild logs  
**URL:** https://us-east-1.console.aws.amazon.com/codesuite/codebuild/projects/it-ops-agent-build/history?region=us-east-1

**Runtime health:** Check runtime status  
```bash
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id it_ops_agent_v2-Od8Y3L7coD \
  --query '{status:status,version:agentRuntimeVersion,updated:lastUpdatedAt}'
```
