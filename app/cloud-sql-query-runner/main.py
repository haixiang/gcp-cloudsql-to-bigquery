'''
This Cloud function runs a query and publishes a list of tables to pubsub.
'''

import base64
import os
import json
import time
import random
from datetime import date
import sqlalchemy
from google.cloud import pubsub_v1

from get_secret import get_secret


def query_runner(event, context):
    """Triggered from a message on a Cloud Pub/Sub topic.
    Args:
      event (dict): Event payload.
      context (google.cloud.functions.Context): Metadata for the event.
    """
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    if pubsub_message == "export":
        project_id = os.environ.get('GCP_PROJECT', '')
        publisher = pubsub_v1.PublisherClient()

        topic_path = publisher.topic_path(
            project_id, os.environ.get('TABLES_LIST_TOPIC_NAME', ''))
        database = os.environ.get('SQL_DB', '')

        sql_user = get_secret(project_id, "sql_user")
        sql_pass = get_secret(project_id, "sql_pass")

        sql_connection_name = get_secret(project_id, "sql_connection_name")

        db = sqlalchemy.create_engine(
            sqlalchemy.engine.url.URL(
                drivername="mysql+pymysql",
                username=sql_user,
                password=sql_pass,
                database=database,
                query={
                    "unix_socket": "/cloudsql/{}".format(sql_connection_name)},
            ),
            pool_size=1,
            # Temporarily exceeds the set pool_size if no connections are available.
            max_overflow=1,
            pool_timeout=30,  # 30 seconds
            pool_recycle=1800  # 30 minutes
        )
        stmt = sqlalchemy.text(os.environ.get('SQL_QUERY'))

        try:
            with db.connect() as conn:
                result = conn.execute(stmt).fetchall()
                export_tables = [r for r, in result]

                # Publish list of tables into Pub/Sub.
                data = ",".join(export_tables)
                data = data.encode("utf-8")
                # Set max number of function re-runs.
                future = publisher.publish(
                    topic_path, data, batch_no="1", max_batches=str(os.environ.get('MAX_BATCHES', 5)))
                print(future.result())
        except Exception as e:
            raise RuntimeError(
                "Failed to execute statement. Exception: {}".format(e))
