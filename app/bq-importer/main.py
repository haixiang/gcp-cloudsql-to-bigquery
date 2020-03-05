'''
This Cloud function imports the csv into BigQuery.
'''
import os
import json
from google.cloud import bigquery
from google.cloud import storage


def bq_importer(data, context):
    if data['name'][-3:] == "csv":
        _, filename = os.path.split(data['name'])
        table_name = filename[:-4]

        client = bigquery.Client()
        dataset_id = os.environ.get('BQ_DATASET', '')

        dataset_ref = client.dataset(dataset_id)
        job_config = bigquery.LoadJobConfig()

        # Get schema from bucket.
        storage_client = storage.Client()
        bucket = storage_client.get_bucket(data['bucket'])
        blob = bucket.blob('schemas/{}.json'.format(table_name))

        schema = json.loads(blob.download_as_string(client=None))
        job_config.schema = schema
        job_config.skip_leading_rows = 0
        job_config.write_disposition = "WRITE_TRUNCATE"  # overwrite table data
        uri = "gs://{bucket}/{file}".format(
            bucket=data['bucket'], file=data['name'])

        load_job = client.load_table_from_uri(
            uri, dataset_ref.table(table_name), job_config=job_config
        )  # API request
        print("Starting export for table {}. Job {}".format(
            table_name, load_job.job_id))

        load_job.result()

        destination_table = client.get_table(dataset_ref.table(table_name))
        print("Loaded {} rows into table {}.".format(
            destination_table.num_rows, table_name))
