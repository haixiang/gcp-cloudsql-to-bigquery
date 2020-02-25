'''
This Cloud function reads csv files from one Cloud Storage bucket, fixes issues with NULL values and exports into another.
'''
import os
from google.cloud import storage
from smart_open import open


def csv_cleaner(data, context):
    # print('Event ID: {}'.format(context.event_id))
    # print('Event type: {}'.format(context.event_type))
    # print('Bucket: {}'.format(data['bucket']))
    # print('File: {}'.format(data['name']))
    # print('Metageneration: {}'.format(data['metageneration']))
    # print('Created: {}'.format(data['timeCreated']))
    # print('Updated: {}'.format(data['updated']))

    # storage_client = storage.Client()

    # bucket = storage_client.bucket(data['bucket'])
    # blob = bucket.blob(data['name'])

    # _, filename = os.path.split(data['name'])
    # raw_file_name = '/tmp/' + filename
    # blob.download_to_filename(raw_file_name)

    # dest_file_name = '/tmp/processed-' + filename

    # # Fixing issue with the NULL values:
    # # https://cloud.google.com/sql/docs/mysql/known-issues#import-export
    # with open(raw_file_name, 'r') as reader, open(dest_file_name, 'w') as writer:
    #     for line in reader:
    #         edited_line = line.replace('"N,', ',')
    #         edited_line = edited_line.replace(',"N\n', ',\n')
    #         writer.write(edited_line)

    # dest_bucket = storage_client.bucket(os.environ.get('DEST_BUCKET', ''))
    # blob = dest_bucket.blob(data['name'])

    # blob.upload_from_filename(dest_file_name)

    # print(
    #     "File {} uploaded to {}.".format(
    #         dest_file_name, data['name']
    #     )
    # )

    ######
    source_file = "gs://{bucket}/{file}".format(
        bucket=data['bucket'], file=data['name'])
    dest_file = "gs://{bucket}/{file}".format(
        bucket=os.environ.get('DEST_BUCKET', ''), file=data['name'])

    # # Fixing issue with the NULL values:
    # # https://cloud.google.com/sql/docs/mysql/known-issues#import-export
    with open(source_file, 'r') as reader, open(dest_file, 'w') as writer:
        for line in reader:
            edited_line = line.replace('"N,', ',')
            edited_line = edited_line.replace(',"N\n', ',\n')
            writer.write(edited_line)

    print("File {} uploaded.".format(data['name']))
