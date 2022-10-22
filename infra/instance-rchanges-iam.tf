/* foo... */


// `AmazonSSMReadOnlyAccess` - 
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "ssm_reader" {
  name = "AmazonSSMReadOnlyAccess"
}

// 
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "rchanges" {
  name               = "rchanges_db_writer"
  assume_role_policy = data.aws_iam_policy_document.ec2_svc_assume_role_policy.json
  managed_policy_arns = [
    data.aws_iam_policy.ssm_reader.arn,
  ]
}

//
// Resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "rchanges" {
  name = "rchanges_profile"
  role = aws_iam_role.rchanges.name
}
