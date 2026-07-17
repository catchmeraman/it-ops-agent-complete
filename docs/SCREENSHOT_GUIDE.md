# 📸 Screenshot Capture Guide

> All resources are LIVE. Open each URL, take a screenshot, save with the filename shown.
> **Account**: 114805761158 | **Region**: us-east-1

---

## Screenshot 1 — AgentCore Runtime Dashboard
**URL**: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes  
**What to capture**: Runtime list showing `it_ops_agent_v2` with status **READY**  
**Save as**: `screenshots/01-agentcore-runtime-dashboard.png`

---

## Screenshot 2 — Runtime Configuration
**URL**: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD  
**What to capture**: Network mode (PUBLIC), idle timeout (900s), max lifetime (28800s)  
**Save as**: `screenshots/02-runtime-configuration.png`

---

## Screenshot 3 — Endpoints Tab
**URL**: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/endpoints  
**What to capture**: Both `DEFAULT` and `itOpsEndpoint` showing READY  
**Save as**: `screenshots/03-endpoints-tab.png`

---

## Screenshot 4 — IAM Role Permissions
**URL**: https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/event-agent-role?section=permissions  
**What to capture**: All 10 inline policies + 2 managed policies  
**Save as**: `screenshots/04-iam-role-permissions.png`

---

## Screenshot 5 — IAM Trust Relationships
**URL**: https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/event-agent-role?section=trust  
**What to capture**: `bedrock-agentcore.amazonaws.com` trusted entity  
**Save as**: `screenshots/05-iam-trust-relationships.png`

---

## Screenshot 6 — Version History
**URL**: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/versions  
**What to capture**: Versions v1 through v8 with timestamps  
**Save as**: `screenshots/06-version-history.png`

---

## Screenshot 7 — itOpsEndpoint Details
**URL**: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/agentcore/runtimes/it_ops_agent_v2-Od8Y3L7coD/endpoints  
**What to capture**: Click into `itOpsEndpoint` — ARN, version, status  
**Save as**: `screenshots/07-endpoint-details.png`

---

## Screenshot 8 — CodePipeline (All Green)
**URL**: https://us-east-1.console.aws.amazon.com/codesuite/codepipeline/pipelines/it-ops-agent-pipeline/view?region=us-east-1  
**What to capture**: Source ✅ Succeeded → Build-Test-Deploy ✅ Succeeded  
**Save as**: `screenshots/08-codepipeline-succeeded.png`

---

## Screenshot 9 — CodeBuild History
**URL**: https://us-east-1.console.aws.amazon.com/codesuite/codebuild/projects/it-ops-agent-build/history?region=us-east-1  
**What to capture**: Build history showing latest Succeeded + earlier Failed attempts  
**Save as**: `screenshots/09-codebuild-history.png`

---

## Screenshot 10 — EventBridge Rule
**URL**: https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/rules/it-ops-agent-code-change  
**What to capture**: Event pattern (CodeCommit source, main branch), Target (Pipeline)  
**Save as**: `screenshots/10-eventbridge-rule.png`

---

## Screenshot 11 — S3 Artifacts
**URL**: https://s3.console.aws.amazon.com/s3/buckets/event-agent-kb-114805761158?region=us-east-1&prefix=devops-outputs/  
**What to capture**: `it-ops-agent.zip` file with size (32MB) and date  
**Save as**: `screenshots/11-s3-artifact.png`

---

## Screenshot 12 — Bedrock Knowledge Base
**URL**: https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/knowledge-bases/84C8RSCN6O  
**What to capture**: Knowledge Base name, status ACTIVE, data source  
**Save as**: `screenshots/12-bedrock-knowledge-base.png`

---

## Screenshot 13 — ECR Repository (Container Images)
**URL**: https://us-east-1.console.aws.amazon.com/ecr/repositories/private/114805761158/bedrock-agentcore-it_ops_agent?region=us-east-1  
**What to capture**: Image list showing `latest` tag + timestamped tags, ARM64  
**Save as**: `screenshots/13-ecr-repository.png`

---

## Screenshot 14 — CloudFormation Stack
**URL**: https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks?filteringText=it-ops-agent-infra  
**What to capture**: Stack `it-ops-agent-infra` status CREATE_COMPLETE, Resources tab  
**Save as**: `screenshots/14-cloudformation-stack.png`

---

## Screenshot 15 — CodeCommit Repository
**URL**: https://us-east-1.console.aws.amazon.com/codesuite/codecommit/repositories/it-ops-agent/browse?region=us-east-1  
**What to capture**: File tree showing main.py, agent.py, tools/, Dockerfile, buildspec.yml  
**Save as**: `screenshots/15-codecommit-repo.png`

---

## Screenshot 16 — SNS Topic
**URL**: https://us-east-1.console.aws.amazon.com/sns/v3/home?region=us-east-1#/topic/arn:aws:sns:us-east-1:114805761158:it-ops-agent-alerts  
**What to capture**: Topic name, ARN, subscriptions  
**Save as**: `screenshots/16-sns-topic.png`

---

## Bonus: Terminal Screenshots

| # | Command to Run | What to Capture |
|---|---------------|-----------------|
| 17 | `./tests/test-scenarios.sh 2` | Agent responding with CloudWatch alarm data |
| 18 | `./tests/test-scenarios.sh 12` | Full multi-tool RCA response |

---

## Quick Capture Order

1. Open all 16 URLs in browser tabs
2. Screenshot each one (Cmd+Shift+4 on Mac)
3. Save to `screenshots/` folder with filenames above
4. Run tests 2 and 12, screenshot terminal output
