# Vault plugin — JSON API

All endpoints live under a project and require a Redmine API key
(`X-Redmine-API-Key` header or `?key=` param). REST API must be enabled in
*Administration → Settings → API*. The acting user needs the matching project
permission: `view_keys` to read, `edit_keys` to write.

Body fields are returned **decrypted** in plaintext (same as the existing
`index.json`), so treat responses as secrets.

## List keys

```
GET /projects/<project>/keys.json
```

Returns an array of key objects.

## Show one key

```
GET /projects/<project>/keys/<id>.json
```

## Create a key

```
POST /projects/<project>/keys.json
Content-Type: application/json
X-Redmine-API-Key: <key>

{
  "vault_key": {
    "type": "Vault::Password",        // or "Vault::KeyFile"
    "name": "db-root",
    "login": "root",
    "body": "s3cret",                 // the secret
    "url": "db.internal:5432",
    "comment": "prod cluster",
    "tags": ["ssh", "prod"]           // array OR "ssh, prod" string
  }
}
```

→ `201 Created` with the key JSON. Invalid input → `422` with
`{"errors":[...]}`. Missing `edit_keys` → `403`.

## Update a key

```
PUT /projects/<project>/keys/<id>.json

{ "vault_key": { "login": "newlogin", "tags": ["mysql"] } }
```

→ `200 OK` with the updated key. Assigning `tags` replaces the existing set.

## Delete a key

```
DELETE /projects/<project>/keys/<id>.json
```

→ `204 No Content`.

## Attach a file (Vault::KeyFile)

For `type=Vault::KeyFile` send the request as **multipart/form-data** (not JSON)
so the file rides along in `vault_key[file]`:

```sh
curl -sS -X POST "https://red.half.net.ua/projects/myproj/keys.json" \
  -H "X-Redmine-API-Key: $RM_KEY" \
  -F "vault_key[type]=Vault::KeyFile" \
  -F "vault_key[name]=deploy-id_ed25519" \
  -F "vault_key[login]=git" \
  -F "vault_key[file]=@./id_ed25519"
```

→ `201` with `"file":"<original-filename>"`. The file contents are stored
**encrypted in the database** (`keys.file_data`); nothing is written to disk.

Download it back (needs `download_keys` permission):

```sh
curl -sS -o id_ed25519 \
  "https://red.half.net.ua/projects/myproj/key_files/<id>/download?key=$RM_KEY"
```

Inline preview: `/projects/<proj>/key_files/<id>/preview`.

> Files are always encrypted at rest (AES-256-GCM, key derived from Redmine's
> `secret_key_base`), independent of the body-cipher setting. See
> `docs/encryption.md`.

## Key object shape

```json
{
  "id": 12,
  "project_id": 1,
  "type": "Vault::Password",
  "name": "db-root",
  "login": "root",
  "body": "s3cret",
  "url": "db.internal:5432",
  "comment": "prod cluster",
  "file": null,
  "tags": ["ssh", "prod"]
}
```

## curl example

```sh
curl -sS -X POST "https://red.half.net.ua/projects/myproj/keys.json" \
  -H "X-Redmine-API-Key: $RM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"vault_key":{"type":"Vault::Password","name":"db-root","login":"root","body":"s3cret","tags":["ssh","prod"]}}'
```
