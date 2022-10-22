/* All resources directly related to the running of MediaCounts and PageViews Glue jobs */

// directory for all mediacounts and pagecounts code - all glue job source code lives here...
//
// note :: requires the user has used AWS glue with the account before - otherwise this folder may not 
// exist (!!)
//
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/s3_bucket
data "aws_s3_bucket" "us_east_1_glue_assets" {
  bucket = "aws-glue-assets-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

// upload pagecounts.py to S3 - location specified in `us_east_1_glue_assets`
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "pagecounts" {
  bucket = data.aws_s3_bucket.us_east_1_glue_assets.bucket
  key    = "scripts/pagecounts.py"
  source = "${path.module}/../glue/pagecounts.py"
  etag   = filemd5("${path.module}/../glue/pagecounts.py")
}

// upload mediacounts.py to S3 - location specified in `us_east_1_glue_assets`
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "mediacounts" {
  bucket = data.aws_s3_bucket.us_east_1_glue_assets.bucket
  key    = "scripts/mediacounts.py"
  source = "${path.module}/../glue/mediacounts.py"
  etag   = filemd5("${path.module}/../glue/mediacounts.py")
}

// defines an hourly trigger that kicks off the pagecounts data job every hour on the hour
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_trigger
resource "aws_glue_trigger" "pagecounts" {
  name        = "pagecounts_hourly"
  description = "an hourly trigger that kicks off the pagecounts data job every hour on the hour"
  enabled     = true
  schedule    = "cron(0 * * * ? *)"
  type        = "SCHEDULED"
  actions {
    job_name = aws_glue_job.pagecounts.name
  }
}

// define a daily trigger that kicks off the mediacounts data job every day at midnight UTC
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_trigger
resource "aws_glue_trigger" "mediacounts" {
  name        = "mediacounts_daily"
  description = "a daily trigger that kicks off the mediacounts data job every day at midnight UTC"
  enabled     = true
  schedule    = "cron(0 0 * * ? *)"
  type        = "SCHEDULED"
  actions {
    job_name = aws_glue_job.mediacounts.name
  }
}

// initialize the pageviews glue job - this job downloads an hour of wikipedia pageview analytics data & writes it to 
// a db (singlestore) and s3 (archive/ athena adhoc)
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job
resource "aws_glue_job" "pagecounts" {

  name        = "pagecounts"
  description = "download an hour of wikipedia pageview analytics data & write to a db (singlestore) and s3 (archive)"
  role_arn    = aws_iam_role.glue_job_adm_worker.arn

  // command parameters
  command {
    name            = "glueetl"
    python_version  = "3" // bug in provider -> prefer 3.9 to default 3.6, not able to specify
    script_location = "s3://${data.aws_s3_bucket.us_east_1_glue_assets.bucket}/scripts/pagecounts.py"
  }

  // job execution parameters
  execution_property {
    // limit concurrent runs s.t. we never have workers spinning up & wasting $$$
    max_concurrent_runs = 2
  }

  // job parameters - limiting resource usage
  timeout      = 10 // in minutes, down from default of 2880 (48 hours)
  max_retries  = 0
  glue_version = "3.0" // use v3.0 for MySQL most recent JDBC driver .jar

  // worker parameters - limiting resource usage
  worker_type       = "G.1X"
  number_of_workers = 2

  // logging, metrics, and performance arguments
  default_arguments = {
    "--enable-continuous-cloudwatch-log"      = "true",
    "--enable-continuous-log-filter"          = "true",
    "--enable-metrics"                        = "true",
    "--enable-s3-parquet-optimized-committer" = "true", // allow for optmized parquet writes (see: https://docs.aws.amazon.com/emr/latest/releaseguide/emr-spark-s3-optimized-committer.html)
    "--ANALYSIS_S3_PATH"                      = var.analysis_bucket
  }
}

// initialize the mediacounts glue job - this job downloads a day of wikipedia media download analytics data & 
// writes it to a db (singlestore) and s3 (archive/athena adhoc)
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job
resource "aws_glue_job" "mediacounts" {

  name        = "mediacounts"
  description = "download a day of wikipedia mediadownload analytics data & write to a db (singlestore) and s3 (archive)"
  role_arn    = aws_iam_role.glue_job_adm_worker.arn

  // command parameters
  command {
    name            = "glueetl"
    python_version  = "3" // bug in provider -> prefer 3.9 to default 3.6, not able to specify
    script_location = "s3://${data.aws_s3_bucket.us_east_1_glue_assets.bucket}/scripts/mediacounts.py"
  }

  // job execution parameters
  execution_property {
    // limit concurrent runs s.t. we never have workers spinning up & wasting $$$
    max_concurrent_runs = 2
  }

  // job parameters - limiting resource usage
  timeout      = 10 // in minutes, down from default of 2880 (48 hours)
  max_retries  = 0
  glue_version = "3.0" // use v3.0 for MySQL most recent JDBC driver .jar

  // worker parameters - limiting resource usage
  worker_type       = "G.1X"
  number_of_workers = 4

  // logging, metrics, and performance arguments
  default_arguments = {
    "--enable-continuous-cloudwatch-log"      = "true",
    "--enable-continuous-log-filter"          = "true",
    "--enable-metrics"                        = "true",
    "--enable-s3-parquet-optimized-committer" = "true", // allow for optmized parquet writes (see: https://docs.aws.amazon.com/emr/latest/releaseguide/emr-spark-s3-optimized-committer.html)
    "--ANALYSIS_S3_PATH"                      = var.analysis_bucket
  }
}