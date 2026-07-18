"""
IT Ops Agent - Agent definition with Strands framework.
Registers all tools and configures the Claude model via Bedrock.
"""
import os
from strands import Agent
from strands.models import BedrockModel

from tools.cloudwatch_tools import get_alarms, get_metric_statistics, list_metrics
from tools.log_tools import search_logs, get_recent_errors
from tools.ssm_tools import run_command, get_command_status
from tools.ec2_tools import describe_instances, manage_instance
from tools.cloudtrail_tools import lookup_recent_changes
from tools.sns_tools import send_notification
from tools.kb_tools import query_runbook

SYSTEM_PROMPT = """You are an expert IT Operations Agent responsible for monitoring, 
diagnosing, and remediating AWS infrastructure issues.

## Your Capabilities:
1. **Diagnostics** - Query CloudWatch metrics/alarms, search logs, check CloudTrail for recent changes
2. **Remediation** - Execute SSM commands on EC2 instances, reboot/stop/start instances
3. **Alerting** - Send SNS notifications to operations teams
4. **Knowledge** - Query runbook Knowledge Base for standard operating procedures

## Operating Principles:
- Always DIAGNOSE before REMEDIATING
- Explain your reasoning and findings clearly
- For destructive actions (reboot, stop), explain why before acting
- Log all remediation actions
- If an issue is outside your capability, say so clearly

## Response Format:
1. Acknowledge the request
2. Diagnostic steps and findings
3. Root cause analysis
4. Remediation action (if applicable)
5. Verification
6. Recommendations for prevention
"""


def create_it_ops_agent() -> Agent:
    """Create and configure the IT Ops Agent with all tools."""

    region = os.environ.get("AWS_REGION", "us-east-1")
    model_id = os.environ.get(
        "BEDROCK_MODEL_ID",
        "anthropic.claude-sonnet-4-6"
    )

    model = BedrockModel(
        model_id=model_id,
        region_name=region
    )

    agent = Agent(
        model=model,
        system_prompt=SYSTEM_PROMPT,
        tools=[
            # Diagnostics
            get_alarms,
            get_metric_statistics,
            list_metrics,
            search_logs,
            get_recent_errors,
            lookup_recent_changes,
            # Remediation
            run_command,
            get_command_status,
            describe_instances,
            manage_instance,
            # Alerting
            send_notification,
            # Knowledge
            query_runbook,
        ]
    )

    return agent
