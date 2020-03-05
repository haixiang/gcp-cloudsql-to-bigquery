'''
Gets a secret from Secret Manager.
'''

from google.cloud import secretmanager_v1beta1 as secretmanager


def get_secret(project_id, secret_id, version="latest"):
    client = secretmanager.SecretManagerServiceClient()

    name = client.secret_version_path(project_id, secret_id, version)
    version = client.access_secret_version(name)

    return version.payload.data.decode('utf-8')
