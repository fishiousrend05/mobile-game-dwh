Mobile Game Data Warehouse (Medallion Architecture)
1. Overview

This project simulates a data warehouse for a mobile game analytics system, designed using the Medallion Architecture (Bronze → Silver → Gold).

It processes raw event data from game clients, transforms it into structured datasets, and delivers analytics-ready data marts for BI tools.

Tech stack:

Data ingestion: MongoDB
Processing: PySpark
Storage: MySQL (Data Warehouse)
Visualization: Power BI
2. Architecture
🔹 Bronze Layer (Raw Data)
Stores raw JSON events from game clients in MongoDB
Preserves full nested structure
No transformation applied

Example event:

{
  "event_uuid": "...",
  "event_name": "tutorial_completed",
  "event_date": "2026-03-26",
  "user": {...},
  "device": {...},
  "event_params": {...}
}
🔹 Silver Layer (Processing & Cleaning)
Flatten nested JSON using PySpark
Clean invalid data and standardize data types
Split data into logical entities

Core tables:

dim_users → user attributes (slow-changing)
fact_events → event-level snapshot
fact_event_params → event-specific attributes
fact_items → item-level details (if applicable)
🔹 Gold Layer (Data Warehouse & Data Marts)
Structured using Star Schema
Optimized for BI queries (MySQL)

Core tables:

dim_users
dim_device
fact_events
fact_progression
fact_purchases
3. Data Marts (Pre-calculated)

Designed for analytics and dashboarding:

mart_dau_mau → Daily / Monthly Active Users
mart_session → session metrics
mart_retention → cohort retention (D1, D7, D30)
mart_funnel → conversion funnel
mart_level_progression → gameplay bottlenecks
mart_arpu → revenue per user
mart_ltv → lifetime value
mart_revenue_daily → daily revenue
4. Key Business Metrics
User Engagement
DAU / MAU
Session metrics
Retention
Day 1 (D1), Day 7 (D7), Day 30 (D30)
Funnel Conversion
Signup → Tutorial → First Purchase
Monetization
ARPU (Average Revenue Per User)
ARPPU (Average Revenue Per Paying User)
5. Data Pipeline
MongoDB (Raw JSON)
        ↓
PySpark (Flatten + Clean)
        ↓
Parquet (Silver layer)
        ↓
MySQL (Star Schema)
        ↓
Data Marts (Pre-aggregated)
        ↓
Power BI Dashboard
6. Project Structure
.
├── bronze/               # Data generation & MongoDB ingestion
├── silver/               # PySpark jobs (cleaning, flattening)
├── data/                 # Parquet output (Silver layer)
├── gold/
│   ├── ddl/              # MySQL schema definitions
│   └── mart/             # SQL for data marts & views
├── build_marts.py        # Orchestration script
├── .env                  # Environment variables
├── setup.py
└── requirements.txt
7. How to Run
1. Setup environment
pip install -r requirements.txt
2. Run Silver layer (PySpark)
python silver/your_spark_job.py
3. Load data to MySQL
python build_marts.py
8. Key Highlights
Designed end-to-end data pipeline (ETL + modeling + BI)
Applied Medallion Architecture in practice
Built analytics-ready data marts
Focused on real business metrics in gaming industry
9. Future Improvements
Add Prefect for orchestration
Implement incremental loading
Optimize partitioning strategy
Add real-time streaming (Kafka)
