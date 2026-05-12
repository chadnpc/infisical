
# verify the interactions and behavior of the module's components when they are integrated together.
Describe "Integration tests: infisical" {
  Context "Secrets Management" {
    <#
    It "Environments CREATE" {
      curl --request POST \
        --url https://us.infisical.com/api/v1/projects/{projectId}/environments \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "name": "<string>",
        "slug": "<string>",
        "position": 2
      }
      '
    }

    It "Environments DELETE" {
    curl --request DELETE \
        --url https://us.infisical.com/api/v1/projects/{projectId}/environments/{id} \
        --header 'Authorization: Bearer <token>'
    }

    It "Environments UPDATE" {
    curl --request PATCH \
        --url https://us.infisical.com/api/v1/projects/{projectId}/environments/{id} \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
        {
        "slug": "<string>",
        "name": "<string>",
        "position": 123
        }
        '
    }


    It "Folders List [GET]" {
    curl --request GET \
    --url https://us.infisical.com/api/v2/folders \
    --header 'Authorization: Bearer <token>'
    }

    It "Folders Get by ID [GET]" {
    curl --request GET \
    --url https://us.infisical.com/api/v2/folders/{id} \
    --header 'Authorization: Bearer <token>'
    }


    It "Folders Create [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v2/folders \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "name": "<string>",
        "path": "/",
        "description": "<string>"
      }
      '
    }


    It "Folders Update [PATCH]" {
    curl --request PATCH \
        --url https://us.infisical.com/api/v2/folders/{folderId} \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "name": "<string>",
        "path": "/",
        "description": "<string>"
      }
      '
    }


    It "Folders Delete [DEL]" {
    curl --request DELETE \
        --url https://us.infisical.com/api/v2/folders/{folderIdOrName} \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "path": "/",
        "forceDelete": false
      }
    '
    }

    It "Secrets List [GET]" {
      curl --request GET \
        --url 'https://us.infisical.com/api/v4/secrets?secretPath=%2F&viewSecretValue=true&expandSecretReferences=true&recursive=false&includePersonalOverrides=false&includeImports=true' \
        --header 'Authorization: Bearer <token>'
    }
  
    It "Secrets Create [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v4/secrets/{secretName} \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "secretValue": "<string>",
        "secretPath": "/",
        "secretComment": "",
        "secretMetadata": [
          {
            "key": "<string>",
            "value": "",
            "isEncrypted": false
          }
        ],
        "tagIds": [
          "<string>"
        ],
        "skipMultilineEncoding": true,
        "type": "shared",
        "secretReminderRepeatDays": 123,
        "secretReminderNote": "<string>"
      }
      '
    }

    It "Secrets Retrieve [GET]" {
    curl --request GET \
      --url 'https://us.infisical.com/api/v4/secrets/{secretName}?secretPath=%2F&type=shared&viewSecretValue=true&expandSecretReferences=true&includeImports=true' \
      --header 'Authorization: Bearer <token>'
    }

    It "Secrets Update [PATCH]" {
    curl --request PATCH \
        --url https://us.infisical.com/api/v4/secrets/{secretName} \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "secretValue": "<string>",
        "secretPath": "/",
        "skipMultilineEncoding": true,
        "type": "shared",
        "tagIds": [
          "<string>"
        ],
        "metadata": {},
        "secretMetadata": [
          {
            "key": "<string>",
            "value": "",
            "isEncrypted": false
          }
        ],
        "secretReminderNote": "<string>",
        "secretReminderRepeatDays": 123,
        "secretReminderRecipients": [
          "<string>"
        ],
        "newSecretName": "<string>",
        "secretComment": "<string>"
      }
      '
    }

    It "Secrets Delete [DEL]" { 
    curl --request DELETE \
        --url https://us.infisical.com/api/v4/secrets/{secretName} \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "secretPath": "/",
        "type": "shared"
      }
      '
    }

    It "Secrets Bulk Create [POST]" {
    curl --request POST \
        --url https://us.infisical.com/api/v4/secrets/batch \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "secrets": [
          {
            "secretKey": "<string>",
            "secretValue": "<string>",
            "secretComment": "",
            "skipMultilineEncoding": true,
            "metadata": {},
            "secretMetadata": [
              {
                "key": "<string>",
                "value": "",
                "isEncrypted": false
              }
            ],
            "tagIds": [
              "<string>"
            ]
          }
        ],
        "secretPath": "/"
      }
      '
    }

    It "Secrets Bulk Update [PATCH]" {
      curl --request PATCH \
        --url https://us.infisical.com/api/v4/secrets/batch \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "secrets": [
          {
            "secretKey": "<string>",
            "secretValue": "<string>",
            "secretPath": "<string>",
            "secretComment": "<string>",
            "skipMultilineEncoding": true,
            "newSecretName": "<string>",
            "tagIds": [
              "<string>"
            ],
            "secretReminderNote": "<string>",
            "secretMetadata": [
              {
                "key": "<string>",
                "value": "",
                "isEncrypted": false
              }
            ],
            "secretReminderRepeatDays": 123
          }
        ],
        "secretPath": "/",
        "mode": "failOnNotFound"
      }
      '
    }

    It "Secrets Bulk Delete [DEL]" {
    curl --request DELETE \
        --url https://us.infisical.com/api/v4/secrets/batch \
        --header 'Authorization: Bearer <token>' \
        --header 'Content-Type: application/json' \
        --data '
      {
        "projectId": "<string>",
        "environment": "<string>",
        "secrets": [
          {
            "secretKey": "<string>",
            "type": "shared"
          }
        ],
        "secretPath": "/"
      }
      '
    }

    It "Secret SyncsList [GET]" {
    curl --request GET \
        --url https://us.infisical.com/api/v1/secret-syncs
    }

    It "Secret Syncs Options [GET]" {
      curl --request GET \
        --url https://us.infisical.com/api/v1/secret-syncs/options
    }
    #>
  }
  # TODO: Add more contexts and tests as needed to cover various integration scenarios.
}
