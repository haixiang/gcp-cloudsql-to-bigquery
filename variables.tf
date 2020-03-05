# Project variables
variable "project" {
  description = "Project ID on GCP."
}

variable "region" {
  description = "Region where you can create services."
  default     = "us-central1"
}

variable "sql_export_topic" {
  description = "Pub/Sub topic to trigger the pipeline."
  default     = "sql-export"
}

variable "sql_tables_list_topic" {
  description = "Pub/Sub topic with messages containing a list of tables to process."
  default     = "sql-tables-list"
}

variable "functions_storage_bucket_name" {
  description = "Storage bucket to upload functions to."
}

variable "export_function_execution_timeout" {
  description = "Timeout setting for the export function."
  default     = 540
}

variable "export_function_max_batches" {
  description = "How many times the export function can re-run to process the remaining tables."
  default     = 8
}

variable "csv_exports_staging_bucket_name" {
  description = "Storage bucket where raw csv files are being uploaded."
}

variable "csv_exports_bucket_name" {
  description = "Storage bucket where csv exports are uploaded."
}

variable "sql_export_cron_schedule" {
  description = "SQL export frequency as a crontab string."
  default     = "0 0 * * *"
}

variable "sql_instance_name" {
  description = "Cloud SQL instance name."
}

variable "sql_db_name" {
  description = "Cloud SQL database name."
}

variable "sql_service_acc" {
  description = "Cloud SQL service account."
}

variable "sql_user" {
  description = "Cloud SQL user."
}

variable "sql_pass" {
  description = "Cloud SQL password."
}

variable "sql_connection_name" {
  description = "Cloud SQL connection name."
}

variable "sql_table_select_query" {
  description = "SQL query to select table names."
  default     = "SELECT table_name FROM information_schema.tables WHERE table_schema = 'default';"
}

variable "bq_dataset" {
  description = "Bigquery dataset to export to."
}
