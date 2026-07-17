output "codecommit_clone_url" {
  description = "CodeCommit HTTPS clone URL"
  value       = aws_codecommit_repository.agent_repo.clone_url_http
}

output "pipeline_name" {
  description = "CodePipeline name"
  value       = aws_codepipeline.agent_pipeline.name
}

output "codebuild_project" {
  description = "CodeBuild project name"
  value       = aws_codebuild_project.agent_build.name
}

output "sns_topic_arn" {
  description = "SNS topic for agent alerts"
  value       = aws_sns_topic.ops_alerts.arn
}

output "agent_runtime_role_arn" {
  description = "IAM role ARN for AgentCore Runtime"
  value       = aws_iam_role.agent_runtime.arn
}

output "eventbridge_rule" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.code_change.name
}
