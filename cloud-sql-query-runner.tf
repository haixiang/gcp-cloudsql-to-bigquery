/*
* SQL query runner function and supporting code.
*/

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
