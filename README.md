# Mobile Game Telemetry Data Warehouse

## Overview

This project is an end-to-end Data Engineering pipeline for a simulated mobile game telemetry system. It generates realistic player data, stores raw events, transforms them using PySpark, safely loads them into MySQL, and builds analytics-ready data marts.
- **Problem solved:** Creates a reliable pipeline for analyzing player engagement, retention, progression funnels, and monetization.
- **Data sources:** Synthetic `users`, `devices`, `events` (e.g., login, level_up), and `purchases` data generated with Faker and stored in MongoDB.
- **Final output:** Silver-layer Parquet files, MySQL dimension/fact tables (Gold), analytical SQL views (Marts), and a Power BI report file (`game_dashboard.pbix`).

##  Architecture


Pipeline flow:

1. Python scripts generate telemetry records and insert them into MongoDB (Bronze Layer).
2. PySpark extracts the data, parses the JSON payload, and writes partitioned Parquet files (Silver Layer).
3. A PySpark JDBC job loads the data into MySQL using an intelligent Upsert mechanism (Gold Layer).
4. SQL scripts aggregate the data into business-ready Data Marts (e.g., `vw_user_journey`, `vw_paying_users`).
5. Prefect orchestrates the entire daily batch pipeline, managing dependencies and logging.
6. Power BI connects to the Gold layer for visual reporting.

## Data Pipeline[cite: 1]

- **Extract / Ingest:** `bronze/generate_bronze_data.py` creates source records in MongoDB simulating real-time player interactions.
- **Transform:** `silver/jobs/process_events.py` reads raw data, enforces data types, flattens nested JSON, and writes clean Parquet files to local storage.
- **Load:** `silver/jobs/load_gold.py` loads Parquet files into MySQL. It uses an `INSERT ... ON DUPLICATE KEY UPDATE` pattern combined with `COALESCE()` to ensure Anti-Null Overwrites (SCD Type 1) for static user attributes.
- **Orchestration:** Prefect is integrated to schedule the workflow, track task execution, and manage retries.
- **Data Quality / Validation:** PySpark filters out invalid event schemas early in the Silver layer, while Gold layer constraints protect historical data integrity.
- **Analytics / Dashboard:** `run_marts.py` executes business rules to construct funnel and retention metrics. `game_dashboard.pbix` is included for Power BI reporting.

## Tech Stack

![Tech Stack](https://skillicons.dev/icons?i=py,mongodb,mysql,git,github)

<p>
  <img src="https://cdn.simpleicons.org/apachespark" height="40" alt="Apache Spark"/>
  <img src="https://cdn.simpleicons.org/prefect" height="40" alt="Prefect"/>
  <img src="https://github.com/microsoft/PowerBI-Icons/blob/main/PNG/Power-BI.png" height="40" alt="Power BI"/>
</p>

## Project Structure

```text
mobile-game-dwh/
|-- bronze/                     # Faker-based source data generator for MongoDB
|-- silver/                     # PySpark jobs (Clean, Standardize, Upsert to Gold)
|-- gold/                       # MySQL DDLs and SQL business rules (Data Marts)
|-- logs/                       # System execution logs
|-- utils/                      # Helper modules (Logger, Config parser)
|-- run_backfill.py             # Script for historical data backfilling
|-- run_marts.py                # Script to execute Data Mart SQL files
|-- game_dashboard.pbix         # Power BI report file
|-- requirements.txt            # Python dependencies
`-- README.md
```


## How to Run

1. Clone the repository

```bash
git clone <repo-url>
cd mobile-game-dwh
```

2. Configure the environment.

```bash
conda create -n game_dwh python=3.10
conda activate game_dwh
pip install -r requirements.txt
```

3. Setup environment variables.

Rename `.env.example` to `.env` and fill in your MongoDB, MySQL, and local storage paths
4. Generate initial data (Bronze).

```bash
python bronze/generate_bronze_data.py
```

5. Run the warehouse pipeline.

```bash
# Transform Bronze -> Silver
python -m silver.jobs.process_events

# Load Silver -> Gold (Backfill over specific dates)
python run_backfill.py --start 2026-01-26 --end 2026-04-17

# Build SQL Marts
python run_marts.py --date 2026-04-17
```

6. Start Orchestration.

```bash
prefect server start
```


## Key Learnings

- Cleaned Parquet files partitioned by date.
- Highly accurate MySQL dimension and fact tables free of null-overwrite errors.
- Pre-aggregated Data Marts ready to answer questions about DAU, MAU, retention, and drop-off rates
- Power BI report file: `game_dashboard.pbix`.


##  Key Learnings

- Designed and implemented a Medallion Data Architecture (Bronze/Silver/Gold) tailored for mobile game telemetry.
- Solved a critical "Anti-Null Overwrite" data corruption issue during Upsert operations between PySpark and MySQL.
- Effectively managed and resolved PySpark and Java JVM environment conflicts (Zombie Java processes) on Windows local development
- Integrated Prefect to transition from manual scripts to a fully orchestrated data pipeline


## Future Improvements
- Refactor raw SQL Data Mart scripts into dbt models for better lineage and testin
- Add structured logging and Slack/Telegram alerts via Prefect upon task failures
