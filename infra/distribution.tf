/*
Manages the Loadbalancer, Certificates, and DNS records for our application (in this case, just Grafana)
assumes the existence of a prexisting public `aws_route53_zone` and domain using AWS nameservers
*/


//
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc
data "aws_vpc" "default" {
  default = true
}

//
// note :: valid as of 4.34.0, will be deprecated in a (near) future version of the provider
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

//
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone
data "aws_route53_zone" "spinach" {
  name         = var.domain
  private_zone = false
}

// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "stats" {
  zone_id         = data.aws_route53_zone.spinach.zone_id
  name            = "stats"
  type            = "CNAME"
  ttl             = 300
  allow_overwrite = true
  records         = [aws_lb.grafana.dns_name]
}


// This resource requires a successful validation of an ACM certificate in concert with other resources.
// see :: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
resource "aws_acm_certificate" "spinach" {
  domain_name       = "*.${var.domain}"
  validation_method = "DNS"
}

// load balancer resources //

// AWS load-balancer micro architecture diagram 
// world -> :443 -> listener (w. cert) -> :3000 -> (target_group - one-of -> (instance_0... instance_i))

// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
resource "aws_lb_listener" "grafana_https" {

  // general 
  load_balancer_arn = aws_lb.grafana.arn

  // SSL support parameters
  port            = "443"
  protocol        = "HTTPS"
  ssl_policy      = "ELBSecurityPolicy-2016-08"
  certificate_arn = aws_acm_certificate.spinach.arn

  //
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "grafana" {
  name                       = "wikipedia-stats-lb"
  internal                   = false
  load_balancer_type         = "application"
  enable_deletion_protection = false
  subnets                    = data.aws_subnet_ids.default.ids // use the default us-east-1 vpc subnets (all zones)
}

//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
resource "aws_lb_target_group" "grafana" {

  // general
  name        = "grafana-target-group"
  port        = var.default_grafana_port
  protocol    = "HTTP"
  target_type = "instance"

  // routing + networking
  vpc_id = data.aws_vpc.default.id

  // health check
  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
    port                = "traffic-port"
    protocol            = "HTTP"
  }
}

//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment
resource "aws_lb_target_group_attachment" "grafana-1" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.grafana.id
  port             = var.default_grafana_port
}


