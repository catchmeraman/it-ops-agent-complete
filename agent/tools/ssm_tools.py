"""AWS Systems Manager tools for running commands on EC2 instances."""
import boto3
import time
from strands import tool


@tool
def run_command(
    instance_ids: list,
    commands: list,
    comment: str = "IT Ops Agent command"
) -> dict:
    """
    Run shell commands on EC2 instances via SSM Run Command.
    
    Args:
        instance_ids: List of EC2 instance IDs (e.g., ["i-0abc123def456"])
        commands: List of shell commands to execute (e.g., ["ps aux --sort=-%mem | head -20"])
        comment: Description of why this command is being run
    
    Returns:
        Dictionary with command ID and initial status
    """
    ssm = boto3.client("ssm")

    response = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName="AWS-RunShellCommand",
        Parameters={"commands": commands},
        Comment=comment,
        TimeoutSeconds=120
    )

    command_id = response["Command"]["CommandId"]

    # Wait briefly for initial status
    time.sleep(3)

    results = []
    for instance_id in instance_ids:
        try:
            invocation = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id
            )
            results.append({
                "instance_id": instance_id,
                "status": invocation["Status"],
                "stdout": invocation.get("StandardOutputContent", "")[:2000],
                "stderr": invocation.get("StandardErrorContent", "")[:500]
            })
        except ssm.exceptions.InvocationDoesNotExist:
            results.append({
                "instance_id": instance_id,
                "status": "PENDING",
                "stdout": "",
                "stderr": ""
            })

    return {
        "command_id": command_id,
        "comment": comment,
        "instance_ids": instance_ids,
        "commands": commands,
        "results": results
    }


@tool
def get_command_status(command_id: str, instance_id: str) -> dict:
    """
    Get the status and output of a previously run SSM command.
    
    Args:
        command_id: The SSM command ID returned from run_command
        instance_id: The EC2 instance ID to check
    
    Returns:
        Dictionary with command status and output
    """
    ssm = boto3.client("ssm")

    try:
        response = ssm.get_command_invocation(
            CommandId=command_id,
            InstanceId=instance_id
        )

        return {
            "command_id": command_id,
            "instance_id": instance_id,
            "status": response["Status"],
            "stdout": response.get("StandardOutputContent", "")[:3000],
            "stderr": response.get("StandardErrorContent", "")[:1000],
            "exit_code": response.get("ResponseCode", -1)
        }
    except Exception as e:
        return {
            "command_id": command_id,
            "instance_id": instance_id,
            "status": "ERROR",
            "error": str(e)
        }
