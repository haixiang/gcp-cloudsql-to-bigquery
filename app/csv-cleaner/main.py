'''
This Cloud function reads csv files from one Cloud Storage bucket, fixes issues with NULL values and exports into another.
'''
import os
from google.cloud import storage
from smart_open import open

from datatype_to_bq import datatype_to_bq


def csv_cleaner(data, context):
    source_file = "gs://{bucket}/{file}".format(
        bucket=data['bucket'], file=data['name'])

    _, filename = os.path.split(data['name'])

    if data['name'][-3:] == "csv":
        dest_file = "gs://{bucket}/csv/{file}".format(
            bucket=os.environ.get('DEST_BUCKET', ''), file=filename)

        # Fixing issue with the NULL values:
        # https://cloud.google.com/sql/docs/mysql/known-issues#import-export
        with open(source_file, 'r') as reader, open(dest_file, 'w') as writer:
            for line in reader:
                edited_line = line.replace('"N,', ',')
                edited_line = edited_line.replace(',"N\n', ',\n')
                writer.write(edited_line)

        print("File {} uploaded.".format(data['name']))
    else:  # process schemas
        dest_file = "gs://{bucket}/schemas/{file}.json".format(
            bucket=os.environ.get('DEST_BUCKET', ''), file=filename.split(".")[0])  # strip extension

        bigquery_schema = []
        with open(source_file, 'r') as reader:
            for line in reader.readlines():
                name, datatype = line.replace(" ", "_").replace(
                    "/", "_and_").replace('"', "").split(",")
                bq_datatype = datatype_to_bq(datatype.upper())
                bigquery_schema.append(
                    ' {{\n   "name": "{}",\n   "type": "{}",\n   "mode": "NULLABLE"\n  }}\n'.format(name, bq_datatype))

        schema = "[\n  {}]".format(",".join(bigquery_schema))
        with open(dest_file, "w") as writer:
            writer.write(schema)

        print("Schema for {} uploaded.".format(filename))
