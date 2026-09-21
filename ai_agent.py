import os
import duckdb
import pandas as pd
from openai import OpenAI

# Local Ollama connection configuration
client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama"
)

DB_PATH = "coffee_shop.duckdb"

def run_ai_agent(user_question: str):
    conn = duckdb.connect(DB_PATH, read_only=True)
    
    # Fetch semantic metadata
    metrics_df = conn.execute("SELECT * FROM metric_definitions").df()
    metric_context = metrics_df.to_dict(orient="records")
    
    system_prompt = f"""
    You are an expert SQL assistant querying a DuckDB coffee shop semantic layer.
    
    Available Metric Definitions:
    {metric_context}
    
    Available Semantic Views:
    - customers_clean (customer_number, app_install_timestamp, app_install_date, gender, marital_status, date_of_birth, installed_through_referral)
    - transactions_clean (transaction_number, customer_number, transaction_timestamp, transaction_date, transaction_month, transaction_hour, day_of_week, store_name, store_city, gross_sale_amount, loyalty_points_used, cash_or_digital_paid, offer_used, offer_name)
    - monthly_business_performance (transaction_month, total_sales, transactions, active_customers, average_transaction_value, repeat_customers, repeat_customer_rate_pct)
    - customer_activity (customer_number, app_install_timestamp, app_install_date, gender, marital_status, date_of_birth, installed_through_referral, first_purchase_timestamp, last_purchase_timestamp, transaction_count, lifetime_sales, average_transaction_value, lifetime_points_used, offer_transactions, is_active_customer, is_repeat_customer)
    - store_performance (store_name, store_city, transactions, customers, total_sales, average_transaction_value, loyalty_points_used, offer_usage_rate_pct)
    - offer_performance (offer_type, transactions, customers, total_sales, average_transaction_value, loyalty_points_redeemed, points_share_of_sales_pct)

    RULES:
    1. Output ONLY valid DuckDB SQL code. Do not include markdown tags or explanation text.
    2. ALWAYS use exact column names listed in the view schemas above.
    3. For monthly metrics, use `transaction_month` (NOT `month`).
    4. If asking for loyalty points by month, JOIN or query `transactions_clean` using `transaction_month` and `SUM(loyalty_points_used)`.
    5. Prefer pre-aggregated views when applicable.
    """
    
    # Call local Ollama model
    sql_response = client.chat.completions.create(
        model="qwen2.5-coder:7b",
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"Generate DuckDB SQL for: {user_question}"}
        ]
    )
    
    generated_sql = sql_response.choices[0].message.content.strip()
    
    # Clean markdown if present
    if generated_sql.startswith("```"):
        generated_sql = "\n".join(generated_sql.split("\n")[1:-1]).strip()
        
    print(f"\n[Generated SQL]:\n{generated_sql}\n")
    
    # Execute query safely
    try:
        query_result = conn.execute(generated_sql).df()
        print(f"[Query Result]:\n{query_result}\n")
    except Exception as e:
        conn.close()
        return f"Database Execution Error: {e}"
    
    # Translate result to business language
    explanation_prompt = f"""
    The business user asked: "{user_question}"
    
    The SQL query produced this table:
   {query_result.to_string(index=False)}
    
    Provide a concise business summary answering the user's question directly.
    """
    
    final_response = client.chat.completions.create(
        model="qwen2.5-coder:7b",
        messages=[{"role": "user", "content": explanation_prompt}]
    )
    
    conn.close()
    return final_response.choices[0].message.content

if __name__ == "__main__":
    prompt = input("Ask a question about your coffee shop data: ")
    answer = run_ai_agent(prompt)
    print(f"[Business Answer]:\n{answer}")