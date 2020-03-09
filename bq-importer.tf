/*
* Bigquery importer function and supporting code.
*/

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
