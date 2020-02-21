provider "google" {
  project = var.project
  region  = var.region
}

provider "archive" {}

locals {
  sql_exporter_sa            = "cloud-sql-exporter"
  export_function_name       = "cloud-sql-exporter"
  sql_query_runner           = "cloud-sql-query-runner"
  query_runner_function_name = "cloud-sql-query-runner"
}

# Enable APIs for the project.
resource "google_project_service" "enable_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage-component.googleapis.com",
    "iam.googleapis.com"
  ])

  service            = each.key
  project            = var.project
  disable_on_destroy = false
}

resource "google_service_account" "sql_exporter_sa" {
  project      = var.project
  account_id   = local.sql_exporter_sa
  display_name = "Cloud SQL Exporter"
  description  = "Service Account for the Cloud Function to perform Cloud SQL exports."

  # SA creation is eventually consistent, need to wait.
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

resource "google_project_iam_member" "sql_exporter_sa_roles" {
  for_each = toset([
    "roles/cloudsql.viewer",
    "roles/cloudsql.client"
  ])
  project = var.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.sql_exporter_sa.email}"
}

# Topic the export cloud function subscribes to.
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
  source_dir  = "./app/${local.export_function_name}"
  output_path = "dist/${local.export_function_name}.zip"
}

# Upload SQL Export function into the bucket.
resource "google_storage_bucket_object" "sql_export_function_code" {
  name   = "${local.export_function_name}.${data.archive_file.sql_export_function_dist.output_md5}.zip"
  bucket = google_storage_bucket.functions_storage.name
  source = data.archive_file.sql_export_function_dist.output_path
}

# Function to perform Cloud SQL export.
resource "google_cloudfunctions_function" "sql_export" {
  name                  = local.export_function_name
  description           = "[Managed by Terraform] This function gets triggered by new messages in the ${google_pubsub_topic.sql_export.name} pubsub topic"
  available_memory_mb   = 512
  runtime               = "python37"
  timeout               = 540
  source_archive_bucket = google_storage_bucket_object.sql_export_function_code.bucket
  source_archive_object = google_storage_bucket_object.sql_export_function_code.name
  entry_point           = "sql_export"
  service_account_email = google_service_account.sql_exporter_sa.email
  region                = var.region
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.sql_export.name
  }
  environment_variables = {
    SQL_INSTANCE  = var.sql_instance_name
    SQL_DB        = var.sql_db_name
    SQL_USER      = var.sql_user
    SQL_PASS      = var.sql_pass
    SQL_CONN_NAME = var.sql_connection_name
    BUCKET        = google_storage_bucket.sql_exports.url
  }
}

# Cloud Storage Bucket with backups.
resource "google_storage_bucket" "sql_exports" {
  name               = var.sql_exports_bucket_name
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

resource "google_storage_bucket_iam_member" "export_bucket_writer" {
  bucket = google_storage_bucket.sql_exports.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.sql_service_acc}"
}
