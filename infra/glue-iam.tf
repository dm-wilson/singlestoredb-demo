/* Define the IAM policies required to allow the Glue jobs to run */

// `AWSGlueServiceRole` - permission to do (everything) needed as a glue service worker - other
// permissions are added as needed based on jobs call
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "glue_svc_role_base" {
  name = "AWSGlueServiceRole"
}

// `AmazonS3FullAccess` - permission to read and write to S3
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "s3_rw" {
  name = "AmazonS3FullAccess"
}

// `CloudWatchFullAccess` - permission to read and write to cloudwatch - used for logging
// job runs + output
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "cloudwatch_rw" {
  name = "CloudWatchFullAccess"
}

// `AmazonSSMReadOnlyAccess` access SSM parameters for the DB (these are stored in SSM) -> see
// main.tf + ssm.tf
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "ssm_ronly" {
  name = "AmazonSSMReadOnlyAccess"
}

// Asssume role document - allows glue service to assume role defined here
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "glue_svc_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

// administrative glue worker - runs glue jobs - see notes on all policies defined above
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "glue_job_adm_worker" {
  name               = "glue_job_adm_worker"
  assume_role_policy = data.aws_iam_policy_document.glue_svc_assume_role_policy.json
  managed_policy_arns = [
    data.aws_iam_policy.glue_svc_role_base.arn,
    data.aws_iam_policy.cloudwatch_rw.arn,
    data.aws_iam_policy.s3_rw.arn,
    data.aws_iam_policy.ssm_ronly.arn
  ]
}