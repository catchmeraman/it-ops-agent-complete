"""EC2 instance management tools for remediation."""
import boto3
from strands import tool


@tool
def describe_instances(
    instance_ids: list = None,
    filters: list = None
) -> dict:
    """
    Describe EC2 instances with their current state and details.
    
    Args:
        instance_ids: Optional list of instance IDs to describe
        filters: Optional list of filters (e.g., [{"Name": "instance-state-name", "Values": ["running"]}])
    
    Returns:
        Dictionary with instance details
    """
    ec2 = boto3.client("ec2")

    params = {}
    if instance_ids:
        params["InstanceIds"] = instance_ids
    if filters:
        params["Filters"] = filters

    response = ec2.describe_instances(**params)

    instances = []
    for reservation in response.get("Reservations", []):
        for inst in reservation.get("Instances", []):
            # Get Name tag
            name = ""
            for tag in inst.get("Tags", []):
                if tag["Key"] == "Name":
                    name = tag["Value"]
                    break

            instances.append({
                "instance_id": inst["InstanceId"],
                "name": name,
                "state": inst["State"]["Name"],
                "type": inst["InstanceType"],
                "az": inst.get("Placement", {}).get("AvailabilityZone", ""),
                "private_ip": inst.get("PrivateIpAddress", ""),
                "public_ip": inst.get("PublicIpAddress", ""),
                "launch_time": inst.get("LaunchTime", "").isoformat()
                if inst.get("LaunchTime") else "",
                "platform": inst.get("PlatformDetails", "Linux/UNIX"),
            })

    return {
        "count": len(instances),
        "instances": instances
    }


@tool
def manage_instance(instance_id: str, action: str) -> dict:
    """
    Perform an action on an EC2 instance (start, stop, reboot).
    
    Args:
        instance_id: The EC2 instance ID (e.g., i-0abc123def456)
        action: Action to perform - start, stop, or reboot
    
    Returns:
        Dictionary with action result and new state
    """
    ec2 = boto3.client("ec2")

    action = action.lower()

    if action == "start":
        response = ec2.start_instances(InstanceIds=[instance_id])
        state = response["StartingInstances"][0]["CurrentState"]["Name"]
    elif action == "stop":
        response = ec2.stop_instances(InstanceIds=[instance_id])
        state = response["StoppingInstances"][0]["CurrentState"]["Name"]
    elif action == "reboot":
        ec2.reboot_instances(InstanceIds=[instance_id])
        state = "rebooting"
    else:
        return {
            "instance_id": instance_id,
            "error": f"Invalid action '{action}'. Use start, stop, or reboot."
        }

    return {
        "instance_id": instance_id,
        "action": action,
        "status": "success",
        "current_state": state
    }
