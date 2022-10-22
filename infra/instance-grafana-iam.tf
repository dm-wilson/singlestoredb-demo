/* Define EC2 Instance Profile */

// asssume role document - allows glue service to assume role defined here
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "ec2_svc_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

//
// see details on athena datasource + permissions here :: https://grafana.com/grafana/plugins/grafana-athena-datasource/
// https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
resource "aws_iam_policy" "grafana_athena_reader" {
  name        = "grafana_athena_reader"
  description = "dev - grafana_athena_reader"

  // terraform's "jsonencode" function converts this  expression result to valid json syntax
  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Sid"    = "AthenaQueryAccess",
        "Effect" = "Allow",
        "Action" = [
          "athena:ListDatabases",
          "athena:ListDataCatalogs",
          "athena:ListWorkGroups",
          "athena:GetDatabase",
          "athena:GetDataCatalog",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetTableMetadata",
          "athena:GetWorkGroup",
          "athena:ListTableMetadata",
          "athena:StartQueryExecution",
          "athena:StopQueryExecution"
        ],
        "Resource" = "*"
      },
      {
        "Sid"    = "GlueReadAccess",
        "Effect" = "Allow",
        "Action" = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ],
        "Resource" = "*"
      },
      {
        "Sid"    = "AthenaS3Access",
        "Effect" = "Allow",
        "Action" = [
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
          "s3:PutObject"
        ],
        "Resource" = [
          "arn:aws:s3:::aws-glue-*",
          "arn:aws:s3:::${var.analysis_bucket}",
          "arn:aws:s3:::${var.analysis_bucket}/*"
        ]
      }
    ]
  })
}


// administrative glue worker - runs glue jobs - see notes on all policies defined above
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "grafana" {
  name               = "grafana_athena_reader"
  assume_role_policy = data.aws_iam_policy_document.ec2_svc_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.grafana_athena_reader.arn,
  ]
}

// Resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "grafana" {
  name = "grafana_reader_profile"
  role = aws_iam_role.grafana.name
}
