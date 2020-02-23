import base64
import os
import json
import time
import random
from datetime import date
import google.auth
from googleapiclient import discovery
from google.cloud import pubsub_v1


def sql_export(event, context):
    """Triggered from a message on a Cloud Pub/Sub topic.
    Args:
      event (dict): Event payload.
      context (google.cloud.functions.Context): Metadata for the event.
    """
    start_time = time.time()
    max_exec_time = int(os.environ.get('MAX_EXEC_TIME', 60))
    instance = os.environ.get('SQL_INSTANCE', '')
    database = os.environ.get('SQL_DB', '')
    bucket = os.environ.get('BUCKET', '')
    tables_str = base64.b64decode(event['data']).decode('utf-8')

    # Check if reached max number of batches.
    batch_no, max_batches = (int(event["attributes"]["batch_no"]),
                             int(event["attributes"]["max_batches"]))
    print("Starting batch {} of {}. Tables to process: {}".format(
        batch_no, max_batches, tables_str))

    if batch_no > max_batches:
        raise RuntimeError("Max number of batches exceeded.")

    # Set role of default cloud function account
    credentials, project_id = google.auth.default()

    service = discovery.build(
        'sqladmin', 'v1beta4', credentials=credentials, cache_discovery=False)

    # Export each table into bucket.
    export_tables = tables_str.split(",")
    while export_tables:
        table = export_tables.pop()
        try:
            body = {  # Database instance export request.
                "exportContext": {  # Database instance export context. # Contains details about the export operation.
                    # This is always sql#exportContext.
                    "kind": "sql#exportContext",
                    "fileType": "CSV",
                    # The path to the file in Google Cloud Storage where the export will be stored. The URI is in the form gs://bucketName/fileName. If the file already exists, the requests succeeds, but the operation fails. If fileType is SQL and the filename ends with .gz, the contents are compressed.
                    "uri": "{bucket}/exports/{date}/{table}.csv".format(bucket=bucket, date=date.today(), table=table),
                    "csvExportOptions": {  # Options for exporting data as CSV.
                        # The select query used to extract the data.
                        "selectQuery": "SELECT * FROM `{}`;".format(table),
                    },
                    "databases": [  # Databases to be exported.
                        database
                    ]
                },
            }
            req = service.instances().export(project=project_id, instance=instance, body=body)
            resp = req.execute()
            service_request = service.operations().get(
                project=project_id, operation=resp["name"])

            # Exponential backoff and retry.
            for n in range(8):
                time.sleep((2 ** n) + (random.randint(0, 1000) / 1000))
                response = service_request.execute()

                if response['status'] == "DONE":
                    break

            print("Table `{}` exported successfully.".format(table))

            # Re-publish the message with remaining tables when timeout approaches.
            if time.time() - start_time > max_exec_time:
                # Publish list of tables into Pub/Sub.
                batch_no += 1
                data = ",".join(export_tables)
                data = data.encode("utf-8")
                publisher = pubsub_v1.PublisherClient()
                topic_path = publisher.topic_path(
                    project_id, os.environ.get('TABLES_LIST_TOPIC_NAME', ''))
                future = publisher.publish(topic_path, data,
                                           batch_no=str(batch_no), max_batches=str(max_batches))
                print(future.result())
                break

        except Exception as e:
            raise RuntimeError(
                "Failed to export table `{}`. Exception: {}".format(table, e))
