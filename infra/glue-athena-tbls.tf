/*
Define the Athena tables and workgroups - these are to be used as a benchmark / alternative to singlestore
analytics queries - not *strictly* needed for application, but used in demo for illustrative purposes
*/

// s3 bucket to write processed parquet files - define athena db from this root
// datasource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
data "aws_s3_bucket" "database" {
  bucket = var.analysis_bucket
}

// provides an athena database
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_database
resource "aws_athena_database" "wikipedia" {
  name   = "wikipedia_analytics"
  bucket = data.aws_s3_bucket.database.bucket
}

//
// resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_workgroup
resource "aws_athena_workgroup" "wikipedia" {
  name = "wikipedia"
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 1073741824 // 1 GiB
  }
}

// define the `pagecounts` table - output from the pagecounts glue job
// Resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table
resource "aws_glue_catalog_table" "pagecounts" {

  // general
  name          = "pagecounts"
  database_name = aws_athena_database.wikipedia.name
  table_type    = "EXTERNAL_TABLE"
  description   = "hourly count of per-page page views across all wikipedia sites, a page view is a response from wikipedia servers with a status of 200 or 304."

  // table properties - enable partition projection to avoid managing a secondary stage/job that 
  // runs MSCK REPAIR following every run
  parameters = {
    "EXTERNAL"               = "true"
    "has_encrypted_data"     = "false"
    "projection.enabled"     = "true"
    "parquet.compression"    = "SNAPPY"
    "projection.date.type"   = "date"
    "projection.date.range"  = "2022-01-01,NOW"
    "projection.date.format" = "yyyy-MM-dd"
  }

  // partitioning & indexing definition 
  partition_index {
    index_name = "date_partition_index"
    keys       = ["date"]
  }

  partition_keys {
    name    = "date"
    type    = "string"
    comment = "the date of pagecount data, in `yyyy-MM-dd` format"
  }

  storage_descriptor {
    // location + auto generated (default) i/o parquet formats
    location      = "s3://${var.analysis_bucket}/pagecounts/pq"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    // serde parameters
    ser_de_info {
      name                  = "pageview-serde"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = 1
      }
    }

    // non-indexed columns - queryable - but not optimized at all...
    columns {
      name    = "project_name"
      type    = "string"
      comment = "the language and project of the requested page, stored as `$language.$project` e.g. `en.m.q` for mobile englsh wikiquotes"
    }

    columns {
      name    = "article_name"
      type    = "string"
      comment = "the url (or, ideally, page title) of the requested page"
    }

    columns {
      name    = "interval_start_unixtime"
      type    = "bigint"
      comment = "the unixtime of the request, rounded down to the hour (based on source file)"
    }

    columns {
      name    = "count"
      type    = "bigint"
      comment = "an integer showing the number of pageviews"
    }
  }
}

// define the `mediacounts` table - output from the mediacounts glue job
// Resource: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_table
resource "aws_glue_catalog_table" "mediacounts" {

  // general
  name          = "mediacounts"
  database_name = aws_athena_database.wikipedia.name
  table_type    = "EXTERNAL_TABLE"
  description   = "counts of how often an image, video, or audio file from upload.wikimedia.org has been transferred to users"

  // table properties - enable partition projection to avoid managing a secondary stage/job that 
  // runs MSCK REPAIR following every run
  parameters = {
    "EXTERNAL"               = "true"
    "has_encrypted_data"     = "false"
    "projection.enabled"     = "true"
    "parquet.compression"    = "SNAPPY"
    "projection.date.type"   = "date"
    "projection.date.range"  = "2022-01-01,NOW"
    "projection.date.format" = "yyyy-MM-dd"
  }

  // partitioning & indexing definition 
  partition_index {
    index_name = "date_partition_index"
    keys       = ["date"]
  }

  partition_keys {
    name    = "date"
    type    = "string"
    comment = "The type of request or connection."
  }

  storage_descriptor {
    // location + auto generated (default) i/o parquet formats
    location      = "s3://${var.analysis_bucket}/mediacounts/pq"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    // serde parameters
    ser_de_info {
      name                  = "pageview-serde"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = 1
      }
    }

    // non-indexed columns - queryable - but not optimized at all...
    columns {
      name    = "filename"
      type    = "string"
      comment = "the name of the raw, original file without the leading"
    }

    columns {
      name    = "total_response_bytes"
      type    = "bigint"
      comment = "total number of response bytes sent to the users for that file and transcodings"
    }

    columns {
      name    = "total_transfers_all"
      type    = "int"
      comment = "total number of transfers (counting both transfers of the raw, original, and thumbnails"
    }
    columns {
      name    = "total_transfers_restricted"
      type    = "int"
      comment = "total number of transfers of the raw, original file (transcodings and thumbnails excluded)"
    }
    columns {
      name    = "total_transfers_transcoded_audio"
      type    = "int"
      comment = "total number of transfers of a file that got transcoded to an audio file"
    }
    columns {
      name    = "total_transfers_transcoded_image"
      type    = "int"
      comment = "total number of transfers of a file that got transcoded to an image file"
    }
    columns {
      name    = "total_transfers_transcoded_mov"
      type    = "int"
      comment = "total number of transfers of a file that got transcoded to a movie file"
    }
    columns {
      name    = "transfers_from_wmf_domain"
      type    = "int"
      comment = "total number of transfers with a referer from a wikimedia foundation domain"
    }
    columns {
      name    = "transfers_from_non_wmf_domain"
      type    = "int"
      comment = "total number of transfers with a referer outside a wikimedia foundation domain"
    }
    columns {
      name    = "transfers_from_invalid_domain"
      type    = "int"
      comment = "total number of transfers with an empty or invalid referer."
    }
  }
}