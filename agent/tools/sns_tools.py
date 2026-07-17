"""SNS tools for sending notifications to operations teams."""
import os
import boto3
from strands import tool


@tool
def send_notification(subject: str, message: str, topic_arn: str = "") -> dict:
    """
    Send an SNS notification to the operations team.
    
    Args:
        subject: Short subject line for the notification
        message: Full notification message body
        topic_arn: SNS topic ARN (uses IT_OPS_SNS_TOPIC env var if empty)
    
    Returns:
        Dictionary with publish result
    """
    sns = boto3.client("sns")

    if not topic_arn:
        topic_arn = os.environ.get("IT_OPS_SNS_TOPIC", "")

    if not topic_arn:
        return {
            "status": "error",
            "error": "No SNS topic ARN provided. Set IT_OPS_SNS_TOPIC env var or pass topic_arn."
        }

    try:
        response = sns.publish(
            TopicArn=topic_arn,
            Subject=subject[:100],  # SNS subject limit
            Message=message
        )

        return {
            "status": "success",
            "message_id": response["MessageId"],
            "topic_arn": topic_arn,
            "subject": subject
        }
    except Exception as e:
        return {
            "status": "error",
            "error": str(e)
        }
