data "aws_caller_identity" "default" {}

module "sns_kms_key_label" {
  source  = "app.terraform.io/SevenPico/context/null"
  version = "1.0.2"
  count   = var.create_kms_key ? 1 : 0
  context = module.context.self
}

module "sns_kms_key" {
  source  = "app.terraform.io/SevenPico/kms-key/aws"
  version = "0.12.1"
  count   = var.create_kms_key ? 1 : 0
  context = module.context.self

  name                = local.create_kms_key ? module.sns_kms_key_label[0].id : ""
  description         = "KMS key for the ${local.alert_for} SNS topic"
  enable_key_rotation = true
  alias               = "alias/${local.alert_for}-sns"
  policy              = var.create_kms_key ? data.aws_iam_policy_document.sns_kms_key_policy[0].json : ""


}

data "aws_iam_policy_document" "sns_kms_key_policy" {
  count = var.create_kms_key ? 1 : 0

  policy_id = "CloudWatchEncryptUsingKey"

  statement {
    effect = "Allow"
    actions = [
      "kms:*"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.default.account_id}:root"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

module "aws_sns_topic_label" {
  source  = "app.terraform.io/SevenPico/context/null"
  version = "1.0.2"
  context = module.context.self
}

resource "aws_sns_topic" "default" {
  count             = local.enabled && var.sns_topic_enabled ? 1 : 0
  name              = module.aws_sns_topic_label.id
  tags              = module.context.tags
  kms_master_key_id = local.create_kms_key ? module.sns_kms_key[0].key_id : var.kms_master_key_id
}

resource "aws_sns_topic_policy" "default" {
  count  = local.enabled && var.sns_policy_enabled && var.sns_topic_enabled ? 1 : 0
  arn    = local.sns_topic_arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "__default_policy_ID"

  statement {
    sid = "__default_statement_ID"

    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    effect    = "Allow"
    resources = [local.sns_topic_arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        "arn:aws:iam::${data.aws_caller_identity.default.account_id}:root",
      ]
    }
  }

  statement {
    sid       = "Allow ${local.alert_for} CloudwatchEvents"
    actions   = ["sns:Publish"]
    resources = [local.sns_topic_arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = local.metric_alarms_arns
    }
  }
}

locals {
  enabled            = module.context.enabled
  create_kms_key     = var.create_kms_key && var.kms_master_key_id == null
  metric_alarms_arns = [for i in aws_cloudwatch_metric_alarm.default : i.arn]
}
