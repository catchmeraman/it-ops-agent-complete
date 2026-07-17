# IT Ops Agent - Complete Implementation

Production-grade IT Operations Agent on Amazon Bedrock AgentCore Runtime with full CI/CD.

## 📁 Project Structure

```
it-ops-agent-complete/
├── agent/                          # Agent source code
│   ├── main.py                     # HTTP server (AgentCore entry point)
│   ├── agent.py                    # Strands Agent definition + system prompt
│   ├── buildspec.yml               # CodeBuild build specification
│   ├── requirements.txt            # Python dependencies
│   └── tools/                      # Agent tool implementations
│       ├── cloudwatch_tools.py     # CloudWatch metrics & alarms
│       ├── log_tools.py            # CloudWatch Logs search
│       ├── ssm_tools.py            # SSM Run Command
│       ├── ec2_tools.py            # EC2 instance management
│       ├── cloudtrail_tools.py     # CloudTrail change tracking
│       ├── sns_tools.py            # SNS notifications
│       └── kb_tools.py             # Bedrock Knowledge Base queries
├── infrastructure/
│   ├── cloudformation/
│   │   └── template.yaml           # Complete CFN template
│   └── terraform/
│       ├── main.tf                 # Complete Terraform config
│       ├── variables.tf            # Input variables
│       └── outputs.tf              # Output values
├── scripts/
│   ├── setup-infrastructure.sh     # One-click infra deploy (CFN)
│   └── deploy.sh                   # Package & deploy agent code
├── tests/
│   └── test-scenarios.sh           # 12 working test scenarios
└── docs/
    └── SCREENSHOT_GUIDE.md         # Exact URLs for all screenshots
```

## 🚀 Quick Start (3 Steps)

### Step 1: Deploy Infrastructure (Choose ONE)

**Option A: CloudFormation** (Recommended)
```bash
cd it-ops-agent-complete
chmod +x scripts/*.sh tests/*.sh

./scripts/setup-infrastructure.sh your-email@company.com
```

**Option B: Terraform**
```bash
cd infrastructure/terraform
terraform init
terraform plan -var="notification_email=your-email@company.com"
terraform apply -var="notification_email=your-email@company.com"
```

### Step 2: Deploy Agent Code
```bash
./scripts/deploy.sh
```

### Step 3: Test
```bash
# Run a single test
./tests/test-scenarios.sh 1

# Run all 12 tests
./tests/test-scenarios.sh
```

## 📸 Screenshots

See [docs/SCREENSHOT_GUIDE.md](docs/SCREENSHOT_GUIDE.md) for exact AWS Console URLs.

## 🏗️ What Gets Created

| Resource | Name | Purpose |
|----------|------|---------|
| CodeCommit | `it-ops-agent` | Source repository |
| CodeBuild | `it-ops-agent-build` | Build, test, deploy |
| CodePipeline | `it-ops-agent-pipeline` | CI/CD orchestration |
| EventBridge | `it-ops-agent-code-change` | Auto-trigger on push |
| SNS Topic | `it-ops-agent-alerts` | Agent notifications |
| IAM Role | `it-ops-agent-runtime-role` | AgentCore execution |
| IAM Role | `it-ops-agent-codebuild-role` | CodeBuild permissions |
| IAM Role | `it-ops-agent-pipeline-role` | Pipeline permissions |

## ⚙️ Configuration

Set these environment variables before deploying:

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | us-east-1 | AWS region |
| `RUNTIME_ID` | it_ops_agent_v2-Od8Y3L7coD | AgentCore Runtime ID |
| `S3_BUCKET` | event-agent-kb-114805761158 | Artifact bucket |
| `ENDPOINT_NAME` | itOpsEndpoint | AgentCore endpoint |

## 🔄 Day-to-Day Workflow

After initial setup, deploying changes is just:
```bash
# Edit agent code
vim agent/tools/ssm_tools.py

# Push to CodeCommit (triggers pipeline automatically)
git add . && git commit -m "feat: add new remediation" && git push

# OR deploy directly
./scripts/deploy.sh
```
