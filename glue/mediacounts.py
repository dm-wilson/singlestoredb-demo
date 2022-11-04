import os
import sys
import time
from datetime import datetime, timezone, timedelta
import urllib.request
import boto3
import uuid

from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

from pyspark.context import SparkContext
from pyspark.sql.types import StructType, StringType, IntegerType, LongType
from pyspark.sql.functions import lit, col, udf

# define mediacounts download parameters -> see warnings on pagecounts job, many of the same apply
BASE_ARGS = ["JOB_NAME", "ANALYSIS_S3_PATH"]
OPTIONAL_ARGS = {"ISO_8601_STRING": datetime.now(timezone.utc).isoformat()}

for opt_arg in OPTIONAL_ARGS.keys():
    if f"--{opt_arg}" in sys.argv:
        BASE_ARGS += opt_arg

args = getResolvedOptions(sys.argv, BASE_ARGS)
args.update(**OPTIONAL_ARGS)

SOURCE_BUCKET = args["ANALYSIS_S3_PATH"]

# offset the execution to T - 1D, don't want to compete w. the archives
t = datetime.strptime(args["ISO_8601_STRING"], "%Y-%m-%dT%H:%M:%S.%f%z") - timedelta(
    days=2
)

pv_year, pv_month, pv_day = t.year, t.month, t.day
MCTS_REMOTE_FULL_URL = f"https://dumps.wikimedia.org/other/mediacounts/daily/{pv_year:04}/mediacounts.{pv_year:04}-{pv_month:02}-{pv_day:02}.v00.tsv.bz2"
MCTS_LOCAL_PATH = os.path.basename(MCTS_REMOTE_FULL_URL)

# define media-counts schema -> this is static across runs of the job
MEDIA_COUNTS_SCHEMA = (
    StructType()
    .add("filename", StringType(), True)
    .add("total_response_bytes", LongType(), True)
    .add("total_transfers_all", IntegerType(), True)
    .add("total_transfers_restricted", IntegerType(), True)
    .add("total_transfers_transcoded_audio", IntegerType(), True)
    .add("_rffu_0", StringType(), True)
    .add("_rffu_1", StringType(), True)
    .add("total_transfers_transcoded_image", IntegerType(), True)
    .add("total_transfers_transcoded_image_200", IntegerType(), True)
    .add("total_transfers_transcoded_image_400", IntegerType(), True)
    .add("total_transfers_transcoded_image_600", IntegerType(), True)
    .add("total_transfers_transcoded_image_800", IntegerType(), True)
    .add("total_transfers_transcoded_image_1000", IntegerType(), True)
    .add("total_transfers_transcoded_image_large", IntegerType(), True)
    .add("_rffu_2", StringType(), True)
    .add("_rffu_3", StringType(), True)
    .add("total_transfers_transcoded_mov", IntegerType(), True)
    .add("total_transfers_transcoded_mov_240", IntegerType(), True)
    .add("total_transfers_transcoded_mov_480", IntegerType(), True)
    .add("total_transfers_transcoded_mov_large", IntegerType(), True)
    .add("_rffu_4", StringType(), True)
    .add("_rffu_5", StringType(), True)
    .add("transfers_from_wmf_domain", IntegerType(), True)
    .add("transfers_from_non_wmf_domain", IntegerType(), True)
    .add("transfers_from_invalid_domain", IntegerType(), True)
)

MCTS_DATA_COLUMNS = [
    "id",
    "filename",
    "_date",
    "total_response_bytes",
    "total_transfers_all",
    "total_transfers_restricted",
    "total_transfers_transcoded_audio",
    "total_transfers_transcoded_image",
    "total_transfers_transcoded_mov",
    "transfers_from_wmf_domain",
    "transfers_from_non_wmf_domain",
    "transfers_from_invalid_domain",
]

MCTS_PARTITION_COLUMNS = ["date"]

# initialize spark session from glueContext
glueContext = GlueContext(SparkContext())
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Download from wikipedia's archive -> local disk attached to Glue (est. 2-3 min.)
# init s3 connection - managed by IAM permissions attached to job
session = boto3.Session(region_name=os.environ.get("AWS_REGION", "us-east-1"))
s3_client = session.client("s3")

urllib.request.urlretrieve(MCTS_REMOTE_FULL_URL, MCTS_LOCAL_PATH)
response = s3_client.upload_file(
    MCTS_LOCAL_PATH,
    SOURCE_BUCKET,
    f"mediacounts/bz/{os.path.basename(MCTS_LOCAL_PATH)}",
)
job.commit()

# NOTE: Spark can read directly from bz2 archive (~750MB); saves some time and space relative to the
# uncompressed (3.5GB), but we're still wasting effort moving data around
media_counts = (
    spark.read.option("header", False)
    .option("delimiter", "\t")
    .schema(MEDIA_COUNTS_SCHEMA)
    .csv(f"s3://{SOURCE_BUCKET}/mediacounts/bz/{os.path.basename(MCTS_LOCAL_PATH)}")
)

# NOTE: mediacounts schema contains *a lot* of stuff we're not interested in -> truncate to 10 relevant cols
obs_uuid = udf(lambda: uuid.uuid4().__str__(), StringType()).asNondeterministic()

media_counts_slim = (
    media_counts.withColumn("id", lit(obs_uuid()))
    .withColumn("_date", lit(f"{pv_year}-{pv_month:02}-{pv_day:02}")) # prefer `_date` to `date` - refrain from using reserved sql keyword 
    .select(MCTS_DATA_COLUMNS + MCTS_PARTITION_COLUMNS)
    .dropDuplicates(["date", "filename"])
)

media_counts_dyn_frame = DynamicFrame.fromDF(
    media_counts_slim, glueContext, "as_dynamic_frame"
)

# output target => parquet on cheap storage -> revist performance on  aws athena / redshift
glueContext.write_dynamic_frame.from_options(
    frame=media_counts_dyn_frame,
    connection_type="s3",
    connection_options={
        "path": f"s3://{SOURCE_BUCKET}/mediacounts/pq/",
        "partitionKeys": MCTS_PARTITION_COLUMNS,
    },
    format="parquet",
)
job.commit()
