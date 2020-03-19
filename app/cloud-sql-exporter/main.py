'''
This Cloud function exports a given list of sql tables into Cloud Storage bucket.
'''

import base64
import os
import json
import time
from datetime import date
import google.auth
from googleapiclient import discovery
from googleapiclient.errors import HttpError
from google.cloud import pubsub_v1

from export_table import export_table


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
    print("Starting batch {} of max {} allowed. Tables to process: {}".format(
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
            print("Starting the export of `{}` table.".format(table))
            # Export table schema.
            query = ("SELECT COLUMN_NAME,DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS "
                     "WHERE TABLE_SCHEMA = '{}' AND TABLE_NAME = '{}' "
                     "ORDER BY ORDINAL_POSITION;").format(database, table)

            export_path = "{bucket}/schemas/{date}/{table}.schema".format(
                bucket=bucket, date=date.today(), table=table)
            export_table(table, query, export_path=export_path, service=service, database=database,
                         project_id=project_id, instance=instance)

            print("Schema for `{}` has been exported successfully.".format(table))

            # Export table data.
            query = "SELECT * FROM `{}`;".format(table)

            export_path = "{bucket}/exports/{date}/{table}.csv".format(
                bucket=bucket, date=date.today(), table=table)
            export_table(table, query, export_path=export_path, service=service, database=database,
                         project_id=project_id, instance=instance)

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
        # Handle more than once event delivery.
        except HttpError as e:
            if e.resp.status == 409:  # Stop the function execution.
                print("Stopping export for table `{}`, as another instance is currently running. Batch {} of {}.".format(
                    table, batch_no, max_batches))
                break

        except Exception as e:
            raise RuntimeError(
                "Failed to export table `{}`. Exception: {}".format(table, e))
