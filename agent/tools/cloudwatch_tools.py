"""CloudWatch tools for metric and alarm diagnostics."""
import boto3
from strands import tool
from datetime import datetime, timedelta


@tool
def get_alarms(state_filter: str = "ALARM") -> dict:
    """
    Get CloudWatch alarms, optionally filtered by state.
    
    Args:
        state_filter: Filter by state - ALARM, OK, INSUFFICIENT_DATA, or ALL for no filter
    
    Returns:
        Dictionary with list of alarms and their details
    """
    cw = boto3.client("cloudwatch")

    if state_filter == "ALL":
        response = cw.describe_alarms()
    else:
        response = cw.describe_alarms(StateValue=state_filter)

    alarms = []
    for alarm in response.get("MetricAlarms", []):
        alarms.append({
            "name": alarm["AlarmName"],
            "state": alarm["StateValue"],
            "reason": alarm.get("StateReason", ""),
            "metric": alarm.get("MetricName", ""),
            "namespace": alarm.get("Namespace", ""),
            "threshold": alarm.get("Threshold"),
            "dimensions": alarm.get("Dimensions", []),
            "updated": alarm.get("StateUpdatedTimestamp", "").isoformat()
            if alarm.get("StateUpdatedTimestamp") else ""
        })

    return {
        "count": len(alarms),
        "state_filter": state_filter,
        "alarms": alarms
    }


@tool
def get_metric_statistics(
    namespace: str,
    metric_name: str,
    dimensions: list,
    period_minutes: int = 60,
    stat: str = "Average"
) -> dict:
    """
    Get CloudWatch metric statistics for a specific metric.
    
    Args:
        namespace: CloudWatch namespace (e.g., AWS/EC2, AWS/RDS)
        metric_name: Metric name (e.g., CPUUtilization, MemoryUtilization)
        dimensions: List of dicts with Name and Value keys (e.g., [{"Name": "InstanceId", "Value": "i-123"}])
        period_minutes: How far back to look in minutes (default 60)
        stat: Statistic type - Average, Maximum, Minimum, Sum, SampleCount
    
    Returns:
        Dictionary with metric datapoints
    """
    cw = boto3.client("cloudwatch")

    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=period_minutes)

    response = cw.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        Dimensions=dimensions,
        StartTime=start_time,
        EndTime=end_time,
        Period=300,  # 5-minute intervals
        Statistics=[stat]
    )

    datapoints = sorted(
        response.get("Datapoints", []),
        key=lambda x: x["Timestamp"]
    )

    formatted_points = []
    for dp in datapoints:
        formatted_points.append({
            "timestamp": dp["Timestamp"].isoformat(),
            "value": dp.get(stat, 0),
            "unit": dp.get("Unit", "")
        })

    return {
        "namespace": namespace,
        "metric": metric_name,
        "dimensions": dimensions,
        "statistic": stat,
        "period_minutes": period_minutes,
        "datapoints": formatted_points,
        "count": len(formatted_points)
    }


@tool
def list_metrics(namespace: str = "", metric_name: str = "") -> dict:
    """
    List available CloudWatch metrics, optionally filtered by namespace or name.
    
    Args:
        namespace: Filter by namespace (e.g., AWS/EC2). Empty for all.
        metric_name: Filter by metric name. Empty for all.
    
    Returns:
        Dictionary with list of available metrics
    """
    cw = boto3.client("cloudwatch")

    params = {}
    if namespace:
        params["Namespace"] = namespace
    if metric_name:
        params["MetricName"] = metric_name

    response = cw.list_metrics(**params)

    metrics = []
    for m in response.get("Metrics", [])[:50]:  # Cap at 50 for readability
        metrics.append({
            "namespace": m["Namespace"],
            "name": m["MetricName"],
            "dimensions": m.get("Dimensions", [])
        })

    return {
        "count": len(metrics),
        "metrics": metrics
    }
