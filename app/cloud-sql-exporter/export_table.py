import time
import random


def export_table(table, query, export_path, service, database, project_id, instance):
    body = {  # Database instance export request.
        "exportContext": {  # Database instance export context. # Contains details about the export operation.
            # This is always sql#exportContext.
            "kind": "sql#exportContext",
            "fileType": "CSV",
            # The path to the file in Google Cloud Storage where the export will be stored. The URI is in the form gs://bucketName/fileName. If the file already exists, the requests succeeds, but the operation fails. If fileType is SQL and the filename ends with .gz, the contents are compressed.
            "uri": export_path,
            "csvExportOptions": {  # Options for exporting data as CSV.
                # The select query used to extract the data.
                "selectQuery": query,
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
            time.sleep(2)
            break
