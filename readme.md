# Wikipedia Analytics on Singlestore

This repo contains the source code for my [submission](https://stats.morespinach.xyz) to the SingleStore 2022 Hackathon. The project uses SingleStore as a database for storing and calculating statistics on Wikipedia's article views and media files served. As of writing, this SingleStore instance is querying over 5 billion article-hour records (~200 GB parquet, ~900 GB raw-uncompressed).
	
## Usage

This repo provisions a Grafana instance with two dashboards for users to interact with, each panel comes with a detailed description of what it displays. Some of these queries rely on the properties of an OLAP DB (e.g. `Media Counts - Total Bytes Served`, `Page Counts - Total Page Views`), while others depend on those of a row-based datastore (e.g. `Page Counts - Total Page Views by Article`) . A summary of the provisioned panels is shown below:

**Table 1.0 - Panels Provisioned**
| Panel                                          | Frequency | Dashboard   |
|------------------------------------------------|-----------|-------------|
| Page Counts - Total Page Views                 | Hourly    | Athena Demo |
| Page Counts - Total Page Views (By Project)    | Hourly    | Athena Demo |
| Page Counts - Total Page Views                 | Hourly    | SingleStore |
| Page Counts - Total Page Views (By Project)    | Hourly    | SingleStore |
| Page Counts - Total Page Views (By Article)    | Hourly    | SingleStore |
| Media Counts - Total Bytes Served              | Daily     | SingleStore |


Users can login to the Grafana instance at `https://stats.morespinach.xyz`.
- read-only credentials (U: `reader`, PW: `Bothus[dot]Lunatus`) are required to authenticate on first visit.

# Architecture

This project performs batch ingestion into SingleStore. Jobs use [Apache Spark](https://spark.apache.org/) running on [AWS Glue](https://aws.amazon.com/glue/features/) to write Wikipedia's [Page Views](https://dumps.wikimedia.org/other/pageviews/readme.html) and [Media Requests](https://dumps.wikimedia.org/other/mediacounts/readme.html) to S3 and are then migrated to Singlestore via an async. background [pipelne](https://docs.singlestore.com/managed-service/en/reference/sql-reference/pipelines-commands/create-pipeline.html). The full system architecture, including some proposed (but eventually rejected) architectures are shown below:

![arch-full](./docs/wikipedia-analytics-arch.png)
