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
  region = "eu-west-1"
}

/*
 * == S3 cost reporter bucket to be replicated
*/

data "aws_s3_bucket" "cost_reporter" {
  bucket = "crayon-vy-prod-bucket"
}

resource "aws_s3_bucket_versioning" "cost_reporter_versioning" {
  bucket = data.aws_s3_bucket.cost_reporter.id
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
      identifiers = ["s3.amazonaws.com", "batchoperations.s3.amazonaws.com"]  # for batch operations
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "replication" {
  name                 = "cur-replication-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = "arn:aws:iam::276520083766:policy/Boundary"
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:PutInventoryConfiguration", # For batch operation replication
      "s3:ListBucket",
    ]

    resources = [data.aws_s3_bucket.cost_reporter.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:InitiateReplication", # batch operations
      "s3:GetObject", # batch operations
      "s3:GetObjectVersion", # batch operations
      "s3:PutObject", # batch operations
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${data.aws_s3_bucket.cost_reporter.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
      "s3:ObjectOwnerOverrideToBucketOwner"
    ]

    resources = ["arn:aws:s3:::846274634169-central-cost-and-usage-reports/*"]
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
  bucket = data.aws_s3_bucket.cost_reporter.id

  rule {
    status = "Enabled"
    id     = "cur_replication_rule"

    destination {
      account       = "846274634169"
      bucket        = "arn:aws:s3:::846274634169-central-cost-and-usage-reports"
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
  bucket = data.aws_s3_bucket.cost_reporter.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
