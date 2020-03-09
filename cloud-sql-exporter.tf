/*
* SQL Exporter function and supporting code.
*/

resource "google_service_account" "sql_exporter" {
  project      = var.project
  account_id   = local.sql_exporter
  display_name = "Cloud SQL Exporter"
  description  = "Service Account for the Cloud Function to perform Cloud SQL exports."

  # SA creation is eventually consistent, need to wait.
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "google_project_iam_member" "sql_exporter_roles" {
  for_each = toset([
    "roles/cloudsql.viewer",
    "roles/pubsub.publisher"
  ])
  project = var.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.sql_exporter.email}"
}

# SQL Export function zip file.
data "archive_file" "sql_export_function_dist" {
  type        = "zip"
  source_dir  = "./app/${local.sql_exporter}"
  output_path = "dist/${local.sql_exporter}.zip"
}

# Upload SQL Export function into the bucket.
resource "google_storage_bucket_object" "sql_export_function_code" {
  name   = "${local.sql_exporter}.${data.archive_file.sql_export_function_dist.output_md5}.zip"
  bucket = google_storage_bucket.functions_storage.name
  source = data.archive_file.sql_export_function_dist.output_path
}

# Function to perform Cloud SQL export.
resource "google_cloudfunctions_function" "sql_export" {
  name                  = local.sql_exporter
  description           = "[Managed by Terraform] This function gets triggered by new messages in the ${google_pubsub_topic.table_list.name} pubsub topic"
  available_memory_mb   = 128
  runtime               = "python37"
  timeout               = var.export_function_execution_timeout
  source_archive_bucket = google_storage_bucket_object.sql_export_function_code.bucket
  source_archive_object = google_storage_bucket_object.sql_export_function_code.name
  entry_point           = "sql_export"
  service_account_email = google_service_account.sql_exporter.email
  region                = var.region
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.table_list.name
  }
  environment_variables = {
    SQL_INSTANCE           = var.sql_instance_name
    SQL_DB                 = var.sql_db_name
    BUCKET                 = google_storage_bucket.csv_exports_staging.url
    MAX_EXEC_TIME          = var.export_function_execution_timeout - 60 # 1 min less than timeout
    MAX_BATCHES            = var.export_function_max_batches
    TABLES_LIST_TOPIC_NAME = var.sql_tables_list_topic
  }
}
