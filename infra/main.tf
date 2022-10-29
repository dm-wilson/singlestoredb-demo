terraform {

  backend "s3" {
    bucket = "dmw2151-state"
    key    = "state_files/wikipedia-analytics-singlestore.tf"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.34.0"
    }
  }
  required_version = ">= 1.0.3"
}

// Providers
provider "aws" {
  region  = "us-east-1"
  profile = "dmw2151"

  default_tags {
    tags = {
      Environment = "pseudo-prod"
      Project     = "singlestore - wikipedia analytics"
    }
  }

}

// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "current" {}

// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region
data "aws_region" "current" {}


// shared + misc variables //

// name of an aws managed key pair to use for ssh within the vpc
variable "ssh_keypair_name" {
  description = "name of an aws managed key pair to use for ssh within the vpc"
  type        = string
  sensitive   = true
  default     = "public-jump-1"
}

// a pre-existing domain (that you own!) using aws nameservers
variable "domain" {
  description = "a pre-existing domain using aws nameservers"
  type        = string
  default     = "morespinach.xyz"
}

// grafana variables //

//  default grafana serving port (virtually always 3000)
variable "default_grafana_port" {
  description = "grafana traffic port"
  type        = number
  default     = 3000
}

// internal to grafana - storage location on the grafana instance where dashboards are stored
variable "grafana_instance_dashboards_dir" {
  type        = string
  default     = "/var/lib/grafana/dashboards/"
  description = "internal to grafana - storage location on the grafana instance where dashboards are stored"
}

variable "grafana_instance_dashboards_group" {
  type        = string
  default     = "wikipedia"
  description = "internal to grafana - storage location on the grafana instance where dashboards are stored"
}

// glue variables //

// target bucket for all parquet files - used in adhoc athena queries
variable "analysis_bucket" {
  type        = string
  description = "target bucket for all parquet files - used in adhoc athena queries"
  default     = "dmw2151-wikipedia"
}

// singlestore DB variables //

// service/host address of singlestoredb
variable "singlestore_dbhost" {
  type        = string
  description = "service/host address of singlestore db"
  default     = "localhost" // for testing with mysql on localhost
  sensitive   = true
}

// service port of singlestore db
variable "singlestore_dbport" {
  type        = number
  description = "service port of singlestore db"
  default     = 3306 // for testing with mysql on localhost
}

// singlestore db writer user password
variable "singlestore_dbpassword" {
  type        = string
  description = "singlestore db writer user password"
  default     = "writer-password" // for testing with mysql on localhost
  sensitive   = true
}

// ip address of grafana instance
output "grafana_instance_ip" {
  description = "ip address of grafana instance"
  value       = aws_instance.grafana.public_ip
}