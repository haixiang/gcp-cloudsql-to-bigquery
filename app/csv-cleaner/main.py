'''
This Cloud function reads csv files from one Cloud Storage bucket, fixes issues with NULL values and exports into another.
'''
import os
from google.cloud import storage
from smart_open import open


def csv_cleaner(data, context):
    source_file = "gs://{bucket}/{file}".format(
        bucket=data['bucket'], file=data['name'])

    _, filename = os.path.split(data['name'])
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
