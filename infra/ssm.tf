/*
SSM parameters - save connection details for singlestoreDB in SSM. Allows streaming and batch jobs to
pull these credentials at runtime from SSM repo.
*/

// saves the service/host address of singlestore db as an SSM parameter
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "dbhost" {
  name        = "/wiki-singlestore/database/host"
  description = "service/host address of singlestore db"
  type        = "SecureString"
  value       = var.singlestore_dbhost
}

// saves the singlestore db writer user password as an SSM parameter
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "dbpassword" {
  name        = "/wiki-singlestore/database/password"
  description = "singlestore db writer user's password"
  type        = "SecureString"
  value       = var.singlestore_dbpassword
}
