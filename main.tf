terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.9.0"
    }
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}


/*
 * == Cost reporting
 */

resource "aws_cur_report_definition" "this" {
  provider                   = aws.us-east-1
  report_name                = "${var.source_account_id}-cur-definition"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_prefix                  = aws_s3_bucket.cost_reporter.id
  s3_bucket                  = aws_s3_bucket.cost_reporter.id
  s3_region                  = "eu-west-1"
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
}

/*
 * == S3 cost reporter bucket to be replicated
*/

resource "aws_s3_bucket" "cost_reporter" {
  bucket = "${var.source_account_id}-source-cur"
}

resource "aws_s3_bucket_versioning" "cost_reporter_versioning" {
  bucket = aws_s3_bucket.cost_reporter.id
  versioning_configuration {
    status = "Enabled"
  }
}


/*
 * == Replication
*/

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "replication" {
  name               = "cur-replication-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.cost_reporter.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.cost_reporter.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:ObjectOwnerOverrideToBucketOwner"
    ]

    resources = ["arn:aws:s3:::${var.central_account_id}-central-cost-and-usage-reports/*"]
  }
}

resource "aws_iam_policy" "replication" {
  name   = "cur-replication-policy"
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

resource "aws_s3_bucket_replication_configuration" "replication" {
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.cost_reporter_versioning]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.cost_reporter.id

  rule {
    status = "Enabled"
    id     = "cur_replication_rule"

    destination {
      account       = var.central_account_id
      bucket        = "arn:aws:s3:::${var.central_account_id}-central-cost-and-usage-reports"
      storage_class = "STANDARD"
      access_control_translation {
        owner = "Destination"
      }
    }
  }
}


/*
 * == Bucket ownership and policy
*/

resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.cost_reporter.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

data "aws_iam_policy_document" "reporter_policy" {
  statement {
    effect  = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy"
    ]

    principals {
      type        = "Service"
      identifiers = [
        "billingreports.amazonaws.com"
      ]
    }

    resources = [aws_s3_bucket.cost_reporter.arn]
  }
  statement {
    effect  = "Allow"
    actions = [
      "s3:PutObject",
    ]

    principals {
      type        = "Service"
      identifiers = [
        "billingreports.amazonaws.com"
      ]
    }

    resources = ["${aws_s3_bucket.cost_reporter.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "reporter_policy" {
  bucket = aws_s3_bucket.cost_reporter.id
  policy = data.aws_iam_policy_document.reporter_policy.json
}