/*
* Secrets for the functions.
*/

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
