/* Configure EC2 Instance for Grafana */

// select the most recent official ubuntu-20.04 image on ARM64, nothing fancy
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  // canonical (the organization) user-id -> this is a constant value in us-east-1 (may publish under another 
  // account in other regions); check here: https://ubuntu.com/server/docs/cloud-images/amazon-ec2
  owners = ["099720109477"]
}

//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "grafana" {

  // general
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t4g.micro"
  associate_public_ip_address = true

  // ssh access - 
  key_name = var.ssh_keypair_name

  // permissions - allows the instance to assume this role...
  iam_instance_profile = aws_iam_instance_profile.grafana.name

  // provisioning - 
  user_data = templatefile(
    "${path.module}/user-data/grafana-init.sh",
    {
      GRAFANA_INSTANCE_DASHBOARDS_DIR   = var.grafana_instance_dashboards_dir,
      GRAFANA_INSTANCE_DASHBOARDS_GROUP = var.grafana_instance_dashboards_group,
    }
  )
  user_data_replace_on_change = true

  tags = {
    Name = "grafana"
  }
}


//
resource "time_sleep" "wait_90_seconds" {
  create_duration = "90s"
  depends_on      = [aws_instance.grafana]
}


//
// resource: https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource
resource "null_resource" "provision" {

  //
  connection {
    type        = "ssh"
    host        = aws_instance.grafana.public_ip
    user        = "ubuntu"
    private_key = file("~/.ssh/${var.ssh_keypair_name}.pem")
  }

  //
  provisioner "file" {
    content = templatefile(
      "${path.module}/user-data/provisioning/datasources/default.yaml",
      {
        ACCOUNT_ID               = data.aws_caller_identity.current.account_id,
        ATHENA_DATABASE          = aws_athena_database.wikipedia.name,
        ATHENA_DATABASE_REGION   = data.aws_region.current.name,
        ATHENA_WORKGROUP         = aws_athena_workgroup.wikipedia.name,
        ATHENA_DATABASE_ROLE_ARN = aws_iam_instance_profile.grafana.arn,
        GRAFANA_MYSQL_HOST       = var.singlestore_dbhost, // warn - passing sensitive vars in other contexts does not preserve status
        GRAFANA_MYSQL_PORT       = var.singlestore_dbport,
        GRAFANA_MYSQL_PASSWORD   = var.singlestore_dbpassword, // warn - passing sensitive vars in other contexts does not preserve status
      }
    )
    destination = "/usr/share/grafana/conf/provisioning/datasources/default.yml"
  }

  //
  provisioner "file" {
    content = templatefile(
      "${path.module}/user-data/provisioning/dashboards/default.yaml",
      {
        GRAFANA_INSTANCE_DASHBOARDS_DIR   = var.grafana_instance_dashboards_dir,
        GRAFANA_INSTANCE_DASHBOARDS_GROUP = var.grafana_instance_dashboards_group,
      }
    )
    destination = "/usr/share/grafana/conf/provisioning/dashboards/default.yml"
  }

  //
  provisioner "file" {
    source      = "${path.module}/../grafana/dashboards/"
    destination = "${var.grafana_instance_dashboards_dir}${var.grafana_instance_dashboards_group}"
  }

  // trigger -> redeploy these files to each new instance (based on rotating instance.arn)
  triggers = {
    instance         = aws_instance.grafana.arn,
    delayaftercreate = time_sleep.wait_90_seconds.id
  }
}
