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

# Bucket to upload the cloud functions source code to.
resource "google_storage_bucket" "functions_storage" {
  name     = var.functions_storage_bucket_name
  location = var.region
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
