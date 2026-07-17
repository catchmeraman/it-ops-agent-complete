variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "it-ops-agent"
}

variable "runtime_id" {
  description = "Existing AgentCore Runtime ID"
  type        = string
  default     = "it_ops_agent_v2-Od8Y3L7coD"
}

variable "endpoint_name" {
  description = "AgentCore endpoint name"
  type        = string
  default     = "itOpsEndpoint"
}

variable "artifact_bucket" {
  description = "S3 bucket for agent code artifacts"
  type        = string
  default     = "event-agent-kb-114805761158"
}

variable "artifact_key" {
  description = "S3 key for the agent zip package"
  type        = string
  default     = "devops-outputs/it-ops-agent.zip"
}

variable "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  type        = string
  default     = "84C8RSCN6O"
}

variable "notification_email" {
  description = "Email for SNS notifications"
  type        = string
  default     = "ops-team@example.com"
}
