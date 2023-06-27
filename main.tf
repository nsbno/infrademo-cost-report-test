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
  report_name                = "cur-report-definition"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_prefix                  = var.central_s3_bucket
  s3_bucket                  = var.central_s3_bucket
  s3_region                  = "eu-west-1"
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
}
