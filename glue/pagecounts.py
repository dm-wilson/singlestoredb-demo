import os
import sys
import time
from datetime import datetime, timezone, timedelta
import urllib.request
import uuid
import boto3

from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

from pyspark.context import SparkContext
from pyspark.sql.types import StructType, StringType, IntegerType, LongType
from pyspark.sql.functions import lit, udf

# define pagecounts download parameters + add optional arguments for (an iota) better job management
BASE_ARGS = ["JOB_NAME", "ANALYSIS_S3_PATH"]
OPTIONAL_ARGS = {"ISO_8601_STRING": datetime.now(timezone.utc).isoformat()}

for opt_arg in OPTIONAL_ARGS.keys():
    if f"--{opt_arg}" in sys.argv:
        BASE_ARGS += opt_arg

args = getResolvedOptions(sys.argv, BASE_ARGS)
args.update(**OPTIONAL_ARGS)

SOURCE_BUCKET = args["ANALYSIS_S3_PATH"]

# note :: in this section, i do two things i'd typically advise (strongly) against...
#
# 1. parsing execution time arguments at runtime -> this isn't a very robust practice, as it makes
# us dependent on jobs succeeding before the time changes, harder to track failures etc...
#
# 2. donwloading the remote file during job run -> this is a little pricey (as in it wastes heavy
# compute time on  network activity), but the reduction in complexixty of the system is probably
# worth the extra $0.20/day vs. configuring a donwload -> S3 job && reading from S3

# offset the execution to T - 1D, don't want to compete w. the archives
t = datetime.strptime(args["ISO_8601_STRING"], "%Y-%m-%dT%H:%M:%S.%f%z") - timedelta(
    days=1
)
pv_year, pv_month, pv_day, pv_hour = t.year, t.month, t.day, t.hour

PCTS_LOCAL_PATH = f"/tmp/{pv_year}{pv_month:02}{pv_day:02}{pv_hour:02}.gz"
PCTS_REMOTE_PATH = f"https://dumps.wikimedia.org/other/pageviews/{pv_year}/{pv_year}-{pv_month}/pageviews-{pv_year}{pv_month:02}{pv_day:02}-{str(pv_hour).zfill(2):0<6}.gz"

# PERIOD_START_UNIXTIME and PARTITIONING_START_UNIXTIME represent the file start timestamp and the partitioning start
# timestamp for this run respectively
PERIOD_START_UNIXTIME = time.mktime((pv_year, pv_month, pv_day, pv_hour, 0, 0, 0, 0, 0))
PARTITIONING_KEY = f"{pv_year}-{pv_month:02}-{pv_day:02}"

# define page-counts schema -> see pagecounts readme for more detail
# readme :: https://dumps.wikimedia.org/other/pageviews/readme.html
PCTS_SCHEMA = (
    StructType()
    .add("project_name", StringType(), True)
    .add("article_name", StringType(), True)
    .add("count", IntegerType(), True)
    .add("_deprecated", StringType(), True)
)

PCTS_DATA_COLUMNS = [
    "id",
    "project_name",
    "article_name",
    "interval_start_unixtime",
    "count",
]

PCTS_PARTITION_COLUMNS = ["date"]

# initialize spark session from glueContext
glueContext = GlueContext(SparkContext())
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# init s3 connection - managed by IAM permissions attached to job
session = boto3.Session(region_name=os.environ.get("AWS_REGION", "us-east-1"))
s3_client = session.client("s3")

# download from wikipedia's archive -> local disk attached to Glue (est. <60s) && send to S3
# then (ughh) download from S3 across multiple workers...
urllib.request.urlretrieve(PCTS_REMOTE_PATH, PCTS_LOCAL_PATH)
response = s3_client.upload_file(
    PCTS_LOCAL_PATH, SOURCE_BUCKET, f"pagecounts/gz/{os.path.basename(PCTS_LOCAL_PATH)}"
)
job.commit()

# read the file from the worker's tmp storage && write input gz file -> dynamic frame
page_counts = (
    spark.read.option("header", False)
    .option("delimiter", " ")
    .schema(PCTS_SCHEMA)
    .csv(f"s3://{SOURCE_BUCKET}/pagecounts/gz/{os.path.basename(PCTS_LOCAL_PATH)}")
)

obs_uuid = udf(lambda: uuid.uuid4().__str__(), StringType()).asNondeterministic()

page_counts_slim = (
    page_counts.withColumn("id", lit(obs_uuid()))
    .withColumn("date", lit(PARTITIONING_KEY))
    .withColumn(
        "interval_start_unixtime", lit(PERIOD_START_UNIXTIME).astype(LongType())
    )
    .select(PCTS_DATA_COLUMNS + PCTS_PARTITION_COLUMNS)
    .dropDuplicates(["project_name", "article_name", "interval_start_unixtime"])
)

page_counts_dyn_frame = DynamicFrame.fromDF(
    page_counts_slim, glueContext, "as_dynamic_frame"
)

# output target => parquet on cheap storage -> revist performance on  aws athena / redshift
glueContext.write_dynamic_frame.from_options(
    frame=page_counts_dyn_frame,
    connection_type="s3",
    connection_options={
        "path": f"s3://{SOURCE_BUCKET}/pagecounts/pq/",
        "partitionKeys": PCTS_PARTITION_COLUMNS,
    },
    format="parquet",
)
job.commit()
