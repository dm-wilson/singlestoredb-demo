/* */

CREATE DATABASE IF NOT EXISTS wikipedia;
USE wikipedia;

-- for the rc-listener
CREATE USER 'writer'@'%' IDENTIFIED BY 'writer-password';
GRANT SELECT,INSERT ON wikipedia.* TO 'writer'@'%';
    
-- for grafana
CREATE USER 'reader'@'%' IDENTIFIED BY 'reader-password';
GRANT SELECT ON wikipedia.* TO 'reader'@'%';

CREATE or REPLACE PIPELINE `pagecounts`
AS LOAD DATA S3 'dmw2151-wikipedia/pagecounts/pq/'
CONFIG '{"region": "us-east-1"}'
CREDENTIALS '{"aws_access_key_id": "a-access-key-id", "aws_secret_access_key": "a-secret-access-key"}'
SKIP DUPLICATE KEY ERRORS
INTO TABLE wikipedia.pagecounts
FORMAT PARQUET (
   id <- id,
   project_name <- project_name,
   interval_start_unixtime <- interval_start_unixtime,
   count <- count
);

START PIPELINE `pagecounts`;

CREATE or REPLACE PIPELINE `mediacounts`
AS LOAD DATA S3 'dmw2151-wikipedia/mediacounts/pq/'
CONFIG '{"region": "us-east-1"}'
CREDENTIALS '{"aws_access_key_id": "a-access-key-id", "aws_secret_access_key": "a-secret-access-key"}'
SKIP DUPLICATE KEY ERRORS
INTO TABLE wikipedia.mediacounts
FORMAT PARQUET (
   id <- id,
   date <- _date,
   total_response_bytes <- total_response_bytes,
   total_transfers_all <- total_transfers_all
);

START PIPELINE `mediacounts`;