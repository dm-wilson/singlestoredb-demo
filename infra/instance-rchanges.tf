/* Configure EC2 Instance for Changes Listener */

//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "rchanges" {

  // general - 
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t4g.micro"
  associate_public_ip_address = true // should be private - oh well...

  // ssh access - 
  key_name = var.ssh_keypair_name

  // permissions - allows the instance to assume this role...
  iam_instance_profile = aws_iam_instance_profile.rchanges.name

  tags = {
    Name = "rchanges"
  }

}
