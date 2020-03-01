#------------------------------------------------------------------------------#
# IAM AssumeRole
#------------------------------------------------------------------------------#

data "aws_iam_policy_document" "ddns_role" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com",
        "events.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "ddns" {
  count              = var.enable_ddns ? 1 : 0
  name               = format("%s-DDNS", local.name)
  assume_role_policy = data.aws_iam_policy_document.ddns_role.json

  tags = {
    Terraform = true
  }
}

#------------------------------------------------------------------------------#
# IAM Policies
#------------------------------------------------------------------------------#

# TODO: restrict access to particular resources
data "aws_iam_policy_document" "ddns" {
  count = var.enable_ddns ? 1 : 0
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [aws_cloudwatch_log_group.ddns[0].arn]
  }

  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:CreateTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "route53:ListHostedZonesByName",
      "route53:ChangeResourceRecordSets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ddns" {
  count  = var.enable_ddns ? 1 : 0
  name   = format("%s-DDNS", local.name)
  role   = aws_iam_role.ddns[0].id
  policy = data.aws_iam_policy_document.ddns[0].json
}

#------------------------------------------------------------------------------#
# Lambda function
#------------------------------------------------------------------------------#

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/ddns/lambda.py"
  output_path = "${path.module}/ddns/lambda.zip"
}

resource "aws_lambda_function" "ddns" {
  count         = var.enable_ddns ? 1 : 0
  function_name = format("%s-DDNS", local.name)
  description   = "Simple dynamic DNS with Route53"

  filename         = "${path.module}/ddns/lambda.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "lambda.handler"
  role             = aws_iam_role.ddns[0].arn
  runtime          = "python3.7"
  memory_size      = 128
  timeout          = 300

  tags = {
    Terraform = true
  }
}

#------------------------------------------------------------------------------#
# Cloudwatch log group
#------------------------------------------------------------------------------#

resource "aws_cloudwatch_log_group" "ddns" {
  count             = var.enable_ddns ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.ddns[0].function_name}"
  retention_in_days = 7

  tags = {
    Terraform = true
  }
}

#------------------------------------------------------------------------------#
# Cloudwatch event trigger
#------------------------------------------------------------------------------#

resource "aws_cloudwatch_event_rule" "ddns" {
  count       = var.enable_ddns ? 1 : 0
  name        = format("%s-DDNS", local.name)
  description = "EC2 instance launch/termination events"

  event_pattern = jsonencode(
    {
      detail-type = [
        "EC2 Instance Launch Successful",
        "EC2 Instance Terminate Successful",
      ]
      source = [
        "aws.autoscaling",
      ]
    }
  )

  tags = {
    Terraform = true
  }
}

resource "aws_cloudwatch_event_target" "ddns" {
  count     = var.enable_ddns ? 1 : 0
  target_id = "lambda"
  rule      = aws_cloudwatch_event_rule.ddns[0].name
  arn       = aws_lambda_function.ddns[0].arn
}

resource "aws_lambda_permission" "ddns" {
  count         = var.enable_ddns ? 1 : 0
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ddns[0].arn
  source_arn    = aws_cloudwatch_event_rule.ddns[0].arn
  principal     = "events.amazonaws.com"
  statement_id  = "allow-cloudwatch-invocation"
}

