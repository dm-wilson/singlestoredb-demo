/* 
initialize db table schemas + singlestore pipelines 
*/

-- create db if dne
CREATE DATABASE IF NOT EXISTS wikipedia; 
USE wikipedia;

-- create pagecounts and mediacounts tables
CREATE TABLE wikipedia.pagecounts (
   project_name VARCHAR(63),
   article_name VARCHAR(255), -- very bad compression on ID (~10% maybe)
   interval_start_unixtime BIGINT,
   count INT,
   UNIQUE INDEX ts_pc_idx (interval_start_unixtime ASC, project_name ASC, article_name ASC)  USING BTREE,
   SHARD KEY(project_name)
) ENGINE = InnoDB;

CREATE TABLE wikipedia.mediacounts (
   filename varchar(1023), -- very bad compression on ID (~10% maybe)
   date varchar(31),
   total_response_bytes bigint,
   total_transfers_all int,
   total_transfers_restricted int,
   total_transfers_transcoded_audio int,
   total_transfers_transcoded_image int,
   total_transfers_transcoded_mov int,
   transfers_from_wmf_domain int,
   transfers_from_non_wmf_domain int,
   transfers_from_invalid_domain int,
   INDEX ts_pc_idx (date),
   SHARD KEY(date)
) ENGINE = InnoDB;

-- for grafana reader and writer roles' secrets ($reader-password, $writer-password) replaced at runtime
-- stored in AWS SSM (see full arch + video for detail)
CREATE USER IF NOT EXISTS 'reader'@'%' IDENTIFIED BY 'reader-password';
GRANT SELECT ON wikipedia.* TO 'reader'@'%';

CREATE USER IF NOT EXISTS 'writer'@'%' IDENTIFIED BY 'writer-password';
GRANT ALL PRIVILEGES ON wikipedia.* TO 'writer'@'%';

-- create pipelines for pagecounts and mediacounts tables 
-- `$aws_access_key_id`, `$aws_secret_access_key` replaced w. real credentials at runtime
CREATE or REPLACE PIPELINE `pagecounts`
AS LOAD DATA S3 'dmw2151-wikipedia/pagecounts/pq/'
CONFIG '{"region": "us-east-1"}'
CREDENTIALS '{"aws_access_key_id": "a-access-key-id", "aws_secret_access_key": "a-secret-access-key"}'
SKIP DUPLICATE KEY ERRORS
INTO TABLE wikipedia.pagecounts
FORMAT PARQUET (
   project_name <- project_name,
   article_name <- article_name,
   interval_start_unixtime <- interval_start_unixtime,
   count <- count
);

-- NOTE: table schema of mediacounts modified s.t. only most relevant info sinks into table 
CREATE or REPLACE PIPELINE `mediacounts`
AS LOAD DATA S3 'dmw2151-wikipedia/mediacounts/pq/'
CONFIG '{"region": "us-east-1"}'
CREDENTIALS '{"aws_access_key_id": "a-access-key-id", "aws_secret_access_key": "a-secret-access-key"}'
SKIP DUPLICATE KEY ERRORS
INTO TABLE wikipedia.mediacounts
FORMAT PARQUET (
   filename <- filename,
   date <- _date,
   total_response_bytes <- total_response_bytes,
   total_transfers_all <- total_transfers_all
);

START PIPELINE `pagecounts`;
START PIPELINE `mediacounts`;