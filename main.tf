provider "google" {
  project = var.project
  region  = var.region
}

provider "google-beta" {
  project = var.project
  region  = var.region
}

provider "archive" {}

locals {
  sql_exporter     = "cloud-sql-exporter"
  sql_query_runner = "cloud-sql-query-runner"
  csv_cleaner      = "csv-cleaner"
  bq_importer      = "bq-importer"
}

# Enable APIs for the project.
resource "google_project_service" "enable_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage-component.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  service            = each.key
  project            = var.project
  disable_on_destroy = false
}

resource "google_service_account" "bq_importer" {
  project      = var.project
  account_id   = local.bq_importer
  display_name = "BigQuery importer"
  description  = "Service Account for the Cloud Function to perform BigQuery imports."

  # SA creation is eventually consistent, need to wait.
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "google_project_iam_member" "bq_importer_roles" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.user"
  ])
  project = var.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.bq_importer.email}"
}

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

resource "google_service_account" "sql_query_runner" {
  project      = var.project
  account_id   = local.sql_query_runner
  display_name = "Cloud SQL Query Runner"
  description  = "Service Account for the Cloud Function to run queries against Cloud SQL."

  # SA creation is eventually consistent, need to wait.
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "google_project_iam_member" "sql_query_runner_roles" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/pubsub.publisher",
    "roles/secretmanager.secretAccessor"
  ])
  project = var.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.sql_query_runner.email}"
}

resource "google_service_account" "csv_cleaner" {
  project      = var.project
  account_id   = local.csv_cleaner
  display_name = "CSV Cleaner"
  description  = "Service Account for the Cloud Function to read CSV files from one bucket, clean them up and export into another one."

  # SA creation is eventually consistent, need to wait.
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "google_project_iam_member" "csv_cleaner_roles" {
  for_each = toset([
    "roles/cloudsql.viewer",
    "roles/pubsub.publisher"
  ])
  project = var.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.csv_cleaner.email}"
}

# Topic with messages containing a list of tables to process.
resource "google_pubsub_topic" "table_list" {
  name = var.sql_tables_list_topic
}

# Topic to trigger the pipeline.
resource "google_pubsub_topic" "sql_export" {
  name = var.sql_export_topic
}

# Send messages into the sql export topic on schedule.
resource "google_cloud_scheduler_job" "sql_export_invoker" {
  name        = "Cloud-SQL-Export-Invoker"
  description = "Trigger Cloud SQL export"
  schedule    = var.sql_export_cron_schedule
  time_zone   = "America/New_York"

  pubsub_target {
    topic_name = google_pubsub_topic.sql_export.id
    data       = base64encode("export")
  }
}

# Bucket to upload the cloud functions source code.
resource "google_storage_bucket" "functions_storage" {
  name     = var.functions_storage_bucket_name
  location = var.region
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

# Keep SQL connection details in secrets manager
resource "google_secret_manager_secret" "sql_user" {
  provider  = google-beta
  secret_id = "sql_user"

  labels = {
    label = "cloud-sql"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "sql_user" {
  provider    = google-beta
  secret      = google_secret_manager_secret.sql_user.id
  secret_data = var.sql_user
}

resource "google_secret_manager_secret" "sql_pass" {
  provider  = google-beta
  secret_id = "sql_pass"

  labels = {
    label = "cloud-sql"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "sql_pass" {
  provider    = google-beta
  secret      = google_secret_manager_secret.sql_pass.id
  secret_data = var.sql_pass
}

resource "google_secret_manager_secret" "sql_connection_name" {
  provider  = google-beta
  secret_id = "sql_connection_name"

  labels = {
    label = "cloud-sql"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "sql_connection_name" {
  provider    = google-beta
  secret      = google_secret_manager_secret.sql_connection_name.id
  secret_data = var.sql_connection_name
}

# Query Runner function zip file.
data "archive_file" "query_runner_function_dist" {
  type        = "zip"
  source_dir  = "./app/${local.sql_query_runner}"
  output_path = "dist/${local.sql_query_runner}.zip"
}

# Upload Query Runner function into the bucket.
resource "google_storage_bucket_object" "query_runner_function_code" {
  name   = "${local.sql_query_runner}.${data.archive_file.query_runner_function_dist.output_md5}.zip"
  bucket = google_storage_bucket.functions_storage.name
  source = data.archive_file.query_runner_function_dist.output_path
}

# Function to perform Cloud SQL queries.
resource "google_cloudfunctions_function" "query_runner" {
  name                  = local.sql_query_runner
  description           = "[Managed by Terraform] This function gets triggered by new messages in the ${google_pubsub_topic.sql_export.name} pubsub topic"
  available_memory_mb   = 128
  runtime               = "python37"
  source_archive_bucket = google_storage_bucket_object.query_runner_function_code.bucket
  source_archive_object = google_storage_bucket_object.query_runner_function_code.name
  entry_point           = "query_runner"
  service_account_email = google_service_account.sql_query_runner.email
  region                = var.region
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.sql_export.name
  }
  environment_variables = {
    TABLES_LIST_TOPIC_NAME = var.sql_tables_list_topic
    SQL_DB                 = var.sql_db_name
    SQL_QUERY              = var.sql_table_select_query
  }
}

# Cloud Storage Bucket with raw csv exports.
resource "google_storage_bucket" "csv_exports_staging" {
  name               = var.csv_exports_staging_bucket_name
  storage_class      = "MULTI_REGIONAL"
  bucket_policy_only = true
  # retention_policy {
  #   retention_period = 2592000 # 30 days
  # }
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 32 # days
    }
  }
}

resource "google_storage_bucket_iam_member" "export_staging_object_creator" {
  bucket = google_storage_bucket.csv_exports_staging.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.sql_service_acc}"
}

resource "google_storage_bucket_iam_member" "export_staging_object_viewer" {
  bucket = google_storage_bucket.csv_exports_staging.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.csv_cleaner.email}"
}

resource "google_storage_bucket_iam_member" "export_staging_bucket_viewer" {
  bucket = google_storage_bucket.csv_exports_staging.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.csv_cleaner.email}"
}

# CSV Cleaner function zip file.
data "archive_file" "csv_cleaner_function_dist" {
  type        = "zip"
  source_dir  = "./app/${local.csv_cleaner}"
  output_path = "dist/${local.csv_cleaner}.zip"
}

# Upload CSV Cleaner function into the bucket.
resource "google_storage_bucket_object" "csv_cleaner_function_code" {
  name   = "${local.csv_cleaner}.${data.archive_file.csv_cleaner_function_dist.output_md5}.zip"
  bucket = google_storage_bucket.functions_storage.name
  source = data.archive_file.csv_cleaner_function_dist.output_path
}

# Function to perform CSV cleanup.
resource "google_cloudfunctions_function" "csv_cleaner" {
  name                  = local.csv_cleaner
  description           = "[Managed by Terraform] This function gets triggered by a file creation in the ${google_storage_bucket.csv_exports_staging.name} bucket."
  available_memory_mb   = 128
  timeout               = 540
  runtime               = "python37"
  source_archive_bucket = google_storage_bucket_object.csv_cleaner_function_code.bucket
  source_archive_object = google_storage_bucket_object.csv_cleaner_function_code.name
  entry_point           = "csv_cleaner"
  service_account_email = google_service_account.csv_cleaner.email
  region                = var.region
  event_trigger {
    event_type = "google.storage.object.finalize"
    resource   = google_storage_bucket.csv_exports_staging.name
  }
  environment_variables = {
    DEST_BUCKET = google_storage_bucket.csv_exports.name
  }
}

# Cloud Storage Bucket with cleaned up csv exports.
resource "google_storage_bucket" "csv_exports" {
  name               = var.csv_exports_bucket_name
  storage_class      = "MULTI_REGIONAL"
  bucket_policy_only = true
  # retention_policy {
  #   retention_period = 2592000 # 30 days
  # }
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 32 # days
    }
  }
}

resource "google_storage_bucket_iam_member" "export_object_creator" {
  bucket = google_storage_bucket.csv_exports.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.csv_cleaner.email}"
}

resource "google_storage_bucket_iam_member" "export_bucket_writer" {
  bucket = google_storage_bucket.csv_exports.name
  role   = "roles/storage.legacyBucketWriter"
  member = "serviceAccount:${google_service_account.csv_cleaner.email}"
}

# BQ Importer function zip file.
data "archive_file" "bq_importer_function_dist" {
  type        = "zip"
  source_dir  = "./app/${local.bq_importer}"
  output_path = "dist/${local.bq_importer}.zip"
}

# Upload BQ Importer function into the bucket.
resource "google_storage_bucket_object" "bq_importer_function_code" {
  name   = "${local.bq_importer}.${data.archive_file.bq_importer_function_dist.output_md5}.zip"
  bucket = google_storage_bucket.functions_storage.name
  source = data.archive_file.bq_importer_function_dist.output_path
}

# Function to perform BQ Import.
resource "google_cloudfunctions_function" "bq_importer" {
  name                  = local.bq_importer
  description           = "[Managed by Terraform] This function gets triggered by a file creation in the ${google_storage_bucket.csv_exports.name} bucket."
  available_memory_mb   = 128
  timeout               = 540
  runtime               = "python37"
  source_archive_bucket = google_storage_bucket_object.bq_importer_function_code.bucket
  source_archive_object = google_storage_bucket_object.bq_importer_function_code.name
  entry_point           = "bq_importer"
  service_account_email = google_service_account.bq_importer.email
  region                = var.region
  event_trigger {
    event_type = "google.storage.object.finalize"
    resource   = google_storage_bucket.csv_exports.name
  }
  environment_variables = {
    BQ_DATASET = var.bq_dataset
  }
}

resource "google_storage_bucket_iam_member" "export_object_viewer" {
  bucket = google_storage_bucket.csv_exports.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.bq_importer.email}"
}

resource "google_storage_bucket_iam_member" "export_bucket_viewer" {
  bucket = google_storage_bucket.csv_exports.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.bq_importer.email}"
}
