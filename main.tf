terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.3.0"
    }
  }
}
provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

/*
 * == Cost explorer
 */

resource "aws_s3_bucket" "cost_reporter" {
  bucket = "infrademo-cost-reporter"
}

resource "aws_athena_database" "cost_reporter_db" {
  name   = "infrademo_cost_reporter_db"
  bucket = aws_s3_bucket.cost_reporter.id
}

/*
 * == Cost reportomg
 */

resource "aws_cur_report_definition" "this" {
  provider                   = aws.us-east-1
  report_name                = "cur-report-definition"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_prefix                  = "infrademo-cost-reporter"
  s3_bucket                  = aws_s3_bucket.cost_reporter.id
  s3_region                  = "eu-west-1"
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
}

resource "aws_s3_bucket_policy" "report_bucket_policy" {
  bucket = aws_s3_bucket.cost_reporter.id
  policy = data.aws_iam_policy_document.report_bucket_policy.json
}


data "aws_iam_policy_document" "report_bucket_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.cost_reporter.arn,
      "${aws_s3_bucket.cost_reporter.arn}/*",
    ]
  }
}

/*
 * == Athena
 */

resource "aws_s3_bucket" "athena_query_results" {
  bucket = "cost-reporter-athena-query-results"
}

resource "aws_s3_bucket_policy" "athena_query_results_policy" {
  bucket = aws_s3_bucket.athena_query_results.id
  policy = data.aws_iam_policy_document.athena_query_results_policy.json
}

resource "aws_athena_workgroup" "cost-reporter-workgroup" {
  name = "cost-reporter-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_query_results.bucket}/output/"
    }
  }
}

data "aws_iam_policy_document" "athena_query_results_policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::689783162268:role/machine-user-grafana"]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.athena_query_results.arn,
      "${aws_s3_bucket.athena_query_results.arn}/*",
    ]
  }
}

/*
 * == Glue Crawler to create athena tables
*/

data "aws_iam_policy_document" "glue_crawler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler_role" {
  name               = "glue_crawler_role"
  assume_role_policy = data.aws_iam_policy_document.glue_crawler_assume_role.json
}

data "aws_iam_policy_document" "glue_crawler_role_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["glue:*"]
    resources = ["*"]
  }
  statement {
    effect  = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetBucketAcl",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [aws_s3_bucket.cost_reporter.arn, "${aws_s3_bucket.cost_reporter.arn}/*"]
  }
  statement {
    effect  = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:/aws-glue/*"]
  }
}

resource "aws_iam_role_policy" "glue_crawler_role_policy" {
  policy = data.aws_iam_policy_document.glue_crawler_role_permissions.json
  role   = aws_iam_role.glue_crawler_role.id
}


resource "aws_glue_catalog_database" "data_db" {
  name = "cost_reporter_glue_db"
}

resource "aws_glue_crawler" "s3_crawler" {
  database_name = aws_glue_catalog_database.data_db.name
  name          = "s3_crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.cost_reporter.bucket}/${aws_cur_report_definition.this.report_name}/${aws_cur_report_definition.this.report_name}"
  }
}