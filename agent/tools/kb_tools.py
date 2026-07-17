"""Bedrock Knowledge Base tools for runbook retrieval."""
import os
import boto3
from strands import tool


@tool
def query_runbook(query: str, knowledge_base_id: str = "") -> dict:
    """
    Query the IT operations runbook Knowledge Base for SOPs and procedures.
    
    Args:
        query: Natural language question about operations procedures
        knowledge_base_id: Bedrock Knowledge Base ID (uses IT_OPS_KB_ID env var if empty)
    
    Returns:
        Dictionary with relevant runbook passages
    """
    if not knowledge_base_id:
        knowledge_base_id = os.environ.get("IT_OPS_KB_ID", "")

    if not knowledge_base_id:
        return {
            "status": "error",
            "error": "No Knowledge Base ID. Set IT_OPS_KB_ID env var or pass knowledge_base_id."
        }

    bedrock = boto3.client("bedrock-agent-runtime")

    try:
        response = bedrock.retrieve(
            knowledgeBaseId=knowledge_base_id,
            retrievalQuery={"text": query},
            retrievalConfiguration={
                "vectorSearchConfiguration": {
                    "numberOfResults": 5
                }
            }
        )

        results = []
        for r in response.get("retrievalResults", []):
            results.append({
                "content": r.get("content", {}).get("text", ""),
                "score": r.get("score", 0),
                "source": r.get("location", {}).get("s3Location", {}).get("uri", "")
            })

        return {
            "query": query,
            "knowledge_base_id": knowledge_base_id,
            "count": len(results),
            "results": results
        }

    except Exception as e:
        return {
            "status": "error",
            "query": query,
            "error": str(e)
        }
