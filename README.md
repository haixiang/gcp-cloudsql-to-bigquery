# Export from Cloud SQL to BigQUery

Pipeline to execute scheduled export of selected tables from Google's Cloud SQL into BigQuery via Cloud Functions. Exports to csv, fixes [issue with the NULL values](https://cloud.google.com/sql/docs/mysql/known-issues#import-export) and imports into BQ.

Terraform setup:

1. Provision the infrastructure provisioner with the roles of:

- Editor
- Security Admin
- Secret Manager Admin

2. Run the plan:

```
terraform apply \
  -var="project=PROJECT_ID" \
  -var="functions_storage_bucket_name=functions_storage_bucket_name" \
  -var="csv_exports_staging_bucket_name=csv_exports_staging_bucket_name" \
  -var="csv_exports_bucket_name=csv_exports_bucket_name" \
  -var="sql_instance_name=sql_instance_name" \
  -var="sql_db_name=default" \
  -var="sql_service_acc=sql_service_acc@gcp-sa-cloud-sql.iam.gserviceaccount.com" \
  -var="sql_user=sql_user" \
  -var="sql_connection_name=PROJECT_ID:REGION:sql_instance_name" \
  -var="sql_pass=sql_pass" \
  -var="sql_table_select_query=SELECT table_name FROM information_schema.tables WHERE (table_name LIKE 'user__field%' OR table_name IN('users')) AND table_schema = 'default';" \
  -var="bq_dataset=bq_dataset_name"
```

3. Disable infrastructure provisioner.
