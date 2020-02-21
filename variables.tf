# Project variables
variable "project" {
  description = "Project ID on GCP."
}

variable "region" {
  description = "Region where you can create services."
  default     = "us-central1"
}

variable "sql_export_topic" {
  description = "Pub/Sub topic the sql exporting function subscribes to."
  default     = "sql-export"
}

variable "functions_storage_bucket_name" {
  description = "Storage bucket to upload functions to."
}

variable "sql_exports_bucket_name" {
  description = "Storage bucket where sql exports are uploaded."
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
