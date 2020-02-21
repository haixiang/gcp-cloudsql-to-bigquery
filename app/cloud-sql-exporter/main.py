import base64
import os
import json
import time
import random
from datetime import date
import google.auth
from googleapiclient import discovery
import sqlalchemy


def sql_export(event, context):
    """Triggered from a message on a Cloud Pub/Sub topic.
    Args:
      event (dict): Event payload.
      context (google.cloud.functions.Context): Metadata for the event.
    """
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    if pubsub_message == "export":
        # Set role of default cloud function account
        credentials, project_id = google.auth.default()
        instance = os.environ.get('SQL_INSTANCE', '')
        database = os.environ.get('SQL_DB', '')
        bucket = os.environ.get('BUCKET', '')

        db = sqlalchemy.create_engine(
            sqlalchemy.engine.url.URL(
                drivername="mysql+pymysql",
                username=os.environ.get('SQL_USER', ''),
                password=os.environ.get('SQL_PASS', ''),
                database=database,
                query={
                    "unix_socket": "/cloudsql/{}".format(os.environ.get('SQL_CONN_NAME', ''))},
            ),
            pool_size=1,
            # Temporarily exceeds the set pool_size if no connections are available.
            max_overflow=1,
            pool_timeout=30,  # 30 seconds
            pool_recycle=1800  # 30 minutes
        )
        stmt = sqlalchemy.text(
            "SELECT TABLE_NAME FROM information_schema.tables "
            "WHERE (table_name LIKE 'user__field%' OR table_name IN('users')) AND table_schema = 'default';"
        )

        try:
            with db.connect() as conn:
                result = conn.execute(stmt).fetchall()
                export_tables = [r for r, in result]
        except Exception as e:
            raise RuntimeError(
                "Executing statement failed. Exception: {}".format(e))

        service = discovery.build(
            'sqladmin', 'v1beta4', credentials=credentials, cache_discovery=False)

        # Export each table into bucket.
        for table in export_tables:
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
            except Exception as e:
                raise RuntimeError(
                    "Failed to export table `{}`. Exception: {}".format(table, e))
