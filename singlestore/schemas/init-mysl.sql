/* initialize db + table schemas on a MySQL compatible DB  */

-- create db if dne
CREATE DATABASE IF NOT EXISTS wikipedia; 

-- recent changes
CREATE TABLE wikipedia.rchanges (
    id VARCHAR(63) PRIMARY KEY, 
    timestamp bigint,
    wiki VARCHAR(63),
    type VARCHAR(15),
    byte_delta int,
    INDEX ts_rc_idx (timestamp)
) ENGINE = InnoDB;

-- pagecounts
CREATE TABLE wikipedia.pagecounts (
    project_name VARCHAR(63),
    article_name VARCHAR(255),
    interval_start_unixtime BIGINT,
    count INT,
    INDEX ts_pc_idx (interval_start_unixtime, project_name)
) ENGINE = InnoDB;

-- mediacounts
CREATE TABLE wikipedia.mediacounts (
    id VARCHAR(63) PRIMARY KEY,
    filename varchar(1023),
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
    INDEX ts_mc_idx (date, filename)
) ENGINE = InnoDB;
