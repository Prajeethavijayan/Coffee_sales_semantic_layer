An end-to-end analytics platform and AI agent built on DuckDB and OpenAI. This project transforms raw CSV transactional data into a structured business semantic layer and provides a natural language to SQL (NL2SQL) interface for querying business performance.

Features
Data Ingestion & Cleaning: Standardizes raw customer, transaction, and item-level data into cleaned, typed relational views.

Semantic Layer & Metrics: Defines key business KPIs (e.g., total sales, active customers, repeat customer rate, loyalty point usage) in centralized SQL views and a metric dictionary.

AI-Powered Natural Language Interface: Translates plain English user questions into optimized DuckDB SQL queries using Ollama, executes the query against the semantic layer, and translates the data into concise business insights.

Tech Stack

Database Engine: DuckDB

Data Processing: SQL, Python (pandas, tabulate)

LLM Engine: Ollama

Environment: Python 3.14 (Virtual Environment)

Semantic Layer Schema

customers_clean: Standardized customer demographics and referral tracking.

transactions_clean: Cleaned transaction log with store locations, payment methods, and discount flags.

items_clean: Item-level breakdown for product performance analysis.

monthly_business_performance: Pre-aggregated monthly aggregates for total sales, active users, ATV, and repeat rates.

metric_definitions: Data dictionary detailing metric names, underlying formulas, source views, and aggregation grains.