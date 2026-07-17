"""CloudWatch Logs tools for log search and error analysis."""
import boto3
from strands import tool
from datetime import datetime, timedelta


@tool
def search_logs(
    log_group: str,
    filter_pattern: str,
    minutes_back: int = 30,
    limit: int = 20
) -> dict:
    """
    Search CloudWatch Logs with a filter pattern.
    
    Args:
        log_group: Log group name (e.g., /aws/lambda/my-function, /var/log/messages)
        filter_pattern: CloudWatch filter pattern (e.g., "ERROR", "[ip, id, user, timestamp, request, status_code=5*, size]")
        minutes_back: How far back to search in minutes (default 30)
        limit: Maximum number of events to return (default 20)
    
    Returns:
        Dictionary with matching log events
    """
    logs = boto3.client("logs")

    end_time = int(datetime.utcnow().timestamp() * 1000)
    start_time = int((datetime.utcnow() - timedelta(minutes=minutes_back)).timestamp() * 1000)

    try:
        response = logs.filter_log_events(
            logGroupName=log_group,
            filterPattern=filter_pattern,
            startTime=start_time,
            endTime=end_time,
            limit=limit
        )

        events = []
        for event in response.get("events", []):
            events.append({
                "timestamp": datetime.fromtimestamp(
                    event["timestamp"] / 1000
                ).isoformat(),
                "message": event["message"].strip(),
                "stream": event.get("logStreamName", "")
            })

        return {
            "log_group": log_group,
            "filter_pattern": filter_pattern,
            "minutes_back": minutes_back,
            "count": len(events),
            "events": events
        }

    except logs.exceptions.ResourceNotFoundException:
        return {
            "log_group": log_group,
            "error": f"Log group '{log_group}' not found",
            "count": 0,
            "events": []
        }


@tool
def get_recent_errors(log_group: str, minutes_back: int = 60) -> dict:
    """
    Get recent ERROR and EXCEPTION messages from a log group.
    
    Args:
        log_group: Log group name to search
        minutes_back: How far back to look (default 60 minutes)
    
    Returns:
        Dictionary with error events grouped by pattern
    """
    logs = boto3.client("logs")

    end_time = int(datetime.utcnow().timestamp() * 1000)
    start_time = int((datetime.utcnow() - timedelta(minutes=minutes_back)).timestamp() * 1000)

    errors = []
    for pattern in ["ERROR", "Exception", "FATAL", "CRITICAL"]:
        try:
            response = logs.filter_log_events(
                logGroupName=log_group,
                filterPattern=pattern,
                startTime=start_time,
                endTime=end_time,
                limit=10
            )

            for event in response.get("events", []):
                errors.append({
                    "pattern": pattern,
                    "timestamp": datetime.fromtimestamp(
                        event["timestamp"] / 1000
                    ).isoformat(),
                    "message": event["message"].strip()[:500],
                    "stream": event.get("logStreamName", "")
                })
        except Exception:
            continue

    return {
        "log_group": log_group,
        "minutes_back": minutes_back,
        "total_errors": len(errors),
        "errors": errors
    }
