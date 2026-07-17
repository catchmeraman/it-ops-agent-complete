#!/bin/bash
# test-scenarios.sh - 12 Working Test Scenarios for IT Ops Agent
# Each test invokes the agent with a real prompt and captures the response.
#
# Prerequisites:
# - AgentCore runtime it_ops_agent_v2-Od8Y3L7coD is READY
# - At least one EC2 instance running with SSM agent
# - CloudWatch has some alarms configured
#
# Usage: ./test-scenarios.sh [test_number]
#   Run all: ./test-scenarios.sh
#   Run one: ./test-scenarios.sh 3

set -e

RUNTIME_ARN="arn:aws:bedrock-agentcore:us-east-1:114805761158:runtime/it_ops_agent_v2-Od8Y3L7coD"
ENDPOINT="itOpsEndpoint"
REGION="us-east-1"
OUTPUT_DIR="/tmp/it-ops-agent-tests"
mkdir -p "$OUTPUT_DIR"

invoke_agent() {
    local test_num="$1"
    local prompt="$2"
    local session_id="test-${test_num}-$(date +%s)-$(openssl rand -hex 8)"
    local outfile="$OUTPUT_DIR/test-${test_num}-output.json"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TEST $test_num"
    echo "Prompt: $prompt"
    echo "Session: $session_id"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    aws bedrock-agentcore invoke-agent-runtime \
        --agent-runtime-arn "$RUNTIME_ARN" \
        --qualifier "$ENDPOINT" \
        --payload "{\"prompt\": \"$prompt\"}" \
        --runtime-session-id "$session_id" \
        "$outfile" \
        --region "$REGION" 2>&1

    if [ -f "$outfile" ]; then
        echo ""
        echo "Response (first 500 chars):"
        cat "$outfile" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response','')[:500])" 2>/dev/null || cat "$outfile" | head -c 500
        echo ""
        echo "✓ Output saved: $outfile"
    else
        echo "✗ No output file generated"
    fi
}

# ═══════════════════════════════════════════
# TEST 1: Health Check
# ═══════════════════════════════════════════
test_1() {
    invoke_agent 1 "Perform a health check. List your available tools and capabilities."
}

# ═══════════════════════════════════════════
# TEST 2: List CloudWatch Alarms
# ═══════════════════════════════════════════
test_2() {
    invoke_agent 2 "Check if there are any CloudWatch alarms currently in ALARM state. Report what you find."
}

# ═══════════════════════════════════════════
# TEST 3: Get CPU Metrics for EC2
# ═══════════════════════════════════════════
test_3() {
    invoke_agent 3 "Get the average CPU utilization for all EC2 instances over the last hour. Which instance has the highest CPU?"
}

# ═══════════════════════════════════════════
# TEST 4: Describe Running Instances
# ═══════════════════════════════════════════
test_4() {
    invoke_agent 4 "List all EC2 instances that are currently running. Show me their instance IDs, names, types, and IPs."
}

# ═══════════════════════════════════════════
# TEST 5: Search Logs for Errors
# ═══════════════════════════════════════════
test_5() {
    invoke_agent 5 "Search the /aws/lambda log groups for any ERROR messages in the last 30 minutes."
}

# ═══════════════════════════════════════════
# TEST 6: CloudTrail - Recent Changes
# ═══════════════════════════════════════════
test_6() {
    invoke_agent 6 "What infrastructure changes were made in the last 2 hours? Check CloudTrail for any EC2, IAM, or security group modifications."
}

# ═══════════════════════════════════════════
# TEST 7: Diagnose High CPU (Full Workflow)
# ═══════════════════════════════════════════
test_7() {
    invoke_agent 7 "I'm getting alerts about high CPU on my EC2 instances. Diagnose the issue: check the alarms, get metrics, and look at CloudTrail for any recent deployments that might have caused it."
}

# ═══════════════════════════════════════════
# TEST 8: Run SSM Command (Disk Usage)
# ═══════════════════════════════════════════
test_8() {
    # NOTE: Replace i-XXXXX with a real instance ID from test 4
    invoke_agent 8 "Check disk usage on running EC2 instances using SSM. Run 'df -h' to see which volumes are getting full."
}

# ═══════════════════════════════════════════
# TEST 9: Run SSM Command (Top Processes)
# ═══════════════════════════════════════════
test_9() {
    invoke_agent 9 "Find the top memory-consuming processes on running EC2 instances. Use SSM to run 'ps aux --sort=-%mem | head -15'."
}

# ═══════════════════════════════════════════
# TEST 10: Send SNS Notification
# ═══════════════════════════════════════════
test_10() {
    invoke_agent 10 "Send a test notification to the ops team via SNS. Subject: 'IT Ops Agent Test'. Message: 'This is a test notification from the IT Ops Agent during validation testing.'"
}

# ═══════════════════════════════════════════
# TEST 11: Knowledge Base Query
# ═══════════════════════════════════════════
test_11() {
    invoke_agent 11 "Query the runbook knowledge base: What is the standard procedure for handling a disk full alert on a production EC2 instance?"
}

# ═══════════════════════════════════════════
# TEST 12: Full Incident Response (Multi-tool)
# ═══════════════════════════════════════════
test_12() {
    invoke_agent 12 "Incident: Multiple CloudWatch alarms fired in the last 15 minutes. Perform a full root cause analysis: 1) Check which alarms are active, 2) Get the metrics for affected resources, 3) Check CloudTrail for recent changes, 4) Provide a summary and recommended next steps."
}

# ═══════════════════════════════════════════
# Run tests
# ═══════════════════════════════════════════
if [ -n "$1" ]; then
    echo "Running test $1 only..."
    test_$1
else
    echo "Running all 12 test scenarios..."
    echo "Output directory: $OUTPUT_DIR"
    for i in $(seq 1 12); do
        test_$i
        echo ""
        sleep 2  # Small delay between tests
    done
    echo ""
    echo "═══════════════════════════════════════════"
    echo "All tests complete. Outputs in: $OUTPUT_DIR"
    echo "═══════════════════════════════════════════"
fi
