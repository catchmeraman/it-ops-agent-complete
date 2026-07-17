terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

#############################################
# SNS Topic for Agent Notifications
#############################################
resource "aws_sns_topic" "ops_alerts" {
  name         = "${var.project_name}-alerts"
  display_name = "IT Ops Agent Alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#############################################
# IAM Role for AgentCore Runtime
#############################################
resource "aws_iam_role" "agent_runtime" {
  name = "${var.project_name}-runtime-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "bedrock-agentcore.amazonaws.com",
            "bedrock.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_access" {
  name = "BedrockAccess"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },
      {
        Sid    = "KnowledgeBase"
        Effect = "Allow"
        Action = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = "arn:aws:bedrock:${local.region}:${local.account_id}:knowledge-base/${var.knowledge_base_id}"
      },
      {
        Sid      = "AgentCore"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_diagnostics" {
  name = "CloudWatchDiagnostics"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:DescribeAlarms",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "logs:FilterLogEvents",
        "logs:GetLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "cloudtrail:LookupEvents",
        "cloudtrail:GetTrailStatus"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ssm_remediation" {
  name = "SSMRemediation"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:DescribeInstanceInformation"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_management" {
  name = "EC2Management"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:RebootInstances",
        "ec2:StartInstances",
        "ec2:StopInstances"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "sns_notifications" {
  name = "SNSNotifications"
  role = aws_iam_role.agent_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish", "sns:ListTopics"]
      Resource = aws_sns_topic.ops_alerts.arn
    }]
  })
}

#############################################
# CodeCommit Repository
#############################################
resource "aws_codecommit_repository" "agent_repo" {
  repository_name = var.project_name
  description     = "IT Operations Agent source code for AgentCore Runtime"
}

#############################################
# IAM Role for CodeBuild
#############################################
resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "CodeBuildPolicy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation"]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket}",
          "arn:aws:s3:::${var.artifact_bucket}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["codecommit:GitPull", "codecommit:GetBranch", "codecommit:GetCommit"]
        Resource = aws_codecommit_repository.agent_repo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:UpdateAgentRuntime",
          "bedrock-agentcore:GetAgentRuntime",
          "bedrock-agentcore:UpdateAgentRuntimeEndpoint",
          "bedrock-agentcore:GetAgentRuntimeEndpoint"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.agent_runtime.arn
      }
    ]
  })
}

#############################################
# CodeBuild Project
#############################################
resource "aws_codebuild_project" "agent_build" {
  name         = "${var.project_name}-build"
  description  = "Build, test, and deploy IT Ops Agent to AgentCore Runtime"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "RUNTIME_ID"
      value = var.runtime_id
    }
    environment_variable {
      name  = "S3_BUCKET"
      value = var.artifact_bucket
    }
    environment_variable {
      name  = "S3_KEY"
      value = var.artifact_key
    }
    environment_variable {
      name  = "ROLE_ARN"
      value = aws_iam_role.agent_runtime.arn
    }
    environment_variable {
      name  = "ENDPOINT_NAME"
      value = var.endpoint_name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

#############################################
# IAM Role for CodePipeline
#############################################
resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "PipelinePolicy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:GetBucketVersioning"]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket}",
          "arn:aws:s3:::${var.artifact_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch", "codecommit:GetCommit",
          "codecommit:UploadArchive", "codecommit:GetUploadArchiveStatus",
          "codecommit:CancelUploadArchive"
        ]
        Resource = aws_codecommit_repository.agent_repo.arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.agent_build.arn
      }
    ]
  })
}

#############################################
# CodePipeline
#############################################
resource "aws_codepipeline" "agent_pipeline" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = var.artifact_bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "CodeCommitSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        RepositoryName       = var.project_name
        BranchName           = "main"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build-Test-Deploy"
    action {
      name             = "BuildAndDeploy"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.agent_build.name
      }
    }
  }
}

#############################################
# EventBridge Rule (auto-trigger on push)
#############################################
resource "aws_iam_role" "eventbridge" {
  name = "${var.project_name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "StartPipeline"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "codepipeline:StartPipelineExecution"
      Resource = aws_codepipeline.agent_pipeline.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "code_change" {
  name        = "${var.project_name}-code-change"
  description = "Trigger pipeline when code is pushed to main branch"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [aws_codecommit_repository.agent_repo.arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceName = ["main"]
    }
  })
}

resource "aws_cloudwatch_event_target" "pipeline_target" {
  rule     = aws_cloudwatch_event_rule.code_change.name
  arn      = aws_codepipeline.agent_pipeline.arn
  role_arn = aws_iam_role.eventbridge.arn
}
