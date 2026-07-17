"""CloudTrail tools for tracking recent infrastructure changes."""
import boto3
from strands import tool
from datetime import datetime, timedelta


@tool
def lookup_recent_changes(
    minutes_back: int = 60,
    event_name: str = "",
    resource_type: str = "",
    username: str = ""
) -> dict:
    """
    Look up recent CloudTrail events to find infrastructure changes.
    
    Args:
        minutes_back: How far back to look in minutes (default 60)
        event_name: Filter by specific event name (e.g., RunInstances, StopInstances)
        resource_type: Filter by resource type (e.g., AWS::EC2::Instance)
        username: Filter by IAM user or role who made the change
    
    Returns:
        Dictionary with recent change events
    """
    ct = boto3.client("cloudtrail")

    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=minutes_back)

    params = {
        "StartTime": start_time,
        "EndTime": end_time,
        "MaxResults": 25
    }

    # Add lookup attributes (CloudTrail only allows one at a time)
    if event_name:
        params["LookupAttributes"] = [
            {"AttributeKey": "EventName", "AttributeValue": event_name}
        ]
    elif resource_type:
        params["LookupAttributes"] = [
            {"AttributeKey": "ResourceType", "AttributeValue": resource_type}
        ]
    elif username:
        params["LookupAttributes"] = [
            {"AttributeKey": "Username", "AttributeValue": username}
        ]

    response = ct.lookup_events(**params)

    events = []
    for event in response.get("Events", []):
        events.append({
            "event_name": event.get("EventName", ""),
            "event_time": event.get("EventTime", "").isoformat()
            if event.get("EventTime") else "",
            "username": event.get("Username", ""),
            "source": event.get("EventSource", ""),
            "resources": [
                {"type": r.get("ResourceType", ""), "name": r.get("ResourceName", "")}
                for r in event.get("Resources", [])
            ],
            "error_code": event.get("ErrorCode", "")
        })

    return {
        "minutes_back": minutes_back,
        "count": len(events),
        "events": events
    }
