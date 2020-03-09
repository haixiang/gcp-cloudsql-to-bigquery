/*
* csv cleaner function and supporting code.
*/

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
