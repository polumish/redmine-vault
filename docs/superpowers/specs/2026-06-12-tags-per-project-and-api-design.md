# Vault plugin — tags fix, per-project tags, write API

## Problem

The forked Vault plugin (branch `redmine-6.1`) has several defects:

1. **Tags cause HTTP 500.** `Vault::Tag.create_from_string` can return an array
   containing `nil` (when a tag name is blank, duplicated, or fails validation).
   Assigning `@key.tags = [..., nil]` raises `ActiveRecord::AssociationTypeMismatch`.
2. **Tags are global.** A tag named `ssh` is shared across every project/client —
   names collide and leak between unrelated clients.
3. **No write API.** Only `index`/`show` accept an API key. `POST`/`PUT`/`DELETE`
   return 403, forcing a brittle web-session + CSRF scraping workaround.
4. **`Vault::Key.import` bug.** `whitelist: rhash['comment']` writes the comment
   value into the whitelist column (copy-paste error); a bare `rescue` hides all
   errors.

Encryption (AES-128-ECB in `VaultCipher`) is weak but **out of scope** this round —
documented only.

## Design

### 1. Null-safe, idempotent tag parsing

```ruby
def self.create_from_string(string, project)
  return [] if string.blank?
  string.downcase.split(/,\s*/).map(&:strip).reject(&:blank?).uniq.map do |name|
    where(project_id: project.id).find_or_create_by(name: name)
  end.select(&:persisted?)
end
```

No `nil` can reach the HABTM setter. `find_or_create_by` makes repeat submissions
idempotent. Callers pass the key's project.

### 2. Per-project tags

- Migration `010_add_project_to_tags`: add `vault_tags.project_id`, unique index
  `[:project_id, :name]`.
- Backfill: set each existing tag's `project_id` from its first linked key
  (names were globally unique, so no `(project_id, name)` collisions arise).
- `validates :name, uniqueness: { scope: :project_id }`.
- Scope lookups to the project: `keys_controller#index` tag search (2 spots),
  `Tag.cloud_for_project`, `Tag.tags_list`.

### 3. Write API

- `accept_api_auth :index, :show, :create, :update, :destroy`. Authorization is
  unchanged (`before_action :authorize` → the API user's `edit_keys` role in the
  project). No CSRF bypass beyond Redmine's standard API-key handling.
- `create`/`update`/`destroy` gain `respond_to { |format| format.api ... }`:
  - create → `201 Created` + key JSON
  - update → `200 OK` + key JSON
  - destroy → `204 No Content`
  - validation failure → `422` + `{ errors: [...] }`
- `tags` accepts a string (`"ssh, prod"`) or an array (`["ssh","prod"]`).
- Key JSON returns the **decrypted** `body` (consistent with existing `index.json`).

Example:

```
POST /projects/<id>/keys.json
X-Redmine-API-Key: <key>
{"vault_key":{"type":"Vault::Password","name":"db-root","login":"root",
              "body":"s3cret","url":"...","comment":"...","tags":["ssh","prod"]}}
```

### 4. Targeted refactors (bug-only, no gold-plating)

- `Vault::Key.import`: `whitelist: rhash['whitelist']`; bare `rescue` → log the error.
- Remove the dead commented-out `tags=` setter on `Vault::Key`.
- Leave the `search_fild` misspelling (cosmetic; renaming risks the JS/view).

### 5. Tests

- `test/unit/tag_test.rb`: normal / duplicate / blank (`"a,,b"`) / case-folding /
  per-project isolation.
- `test/functional/keys_controller_test.rb`: HTML create with tags (no 500);
  API create/update/destroy via API key; `422` on invalid input.
- Run locally if a Redmine checkout is available; otherwise hand to the user.

### 6. Encryption (documentation only)

Add a note describing the AES-128-ECB weakness (deterministic, no IV, no auth tag)
and recommending the existing `RedmineCipher` (AES-256-CBC) engine via the settings
toggle. No data change this round.

## Out of scope

- Switching/encrypting key bodies to a new cipher.
- Full split of tags shared across multiple projects (best-effort backfill only).
- Renaming the `search_fild` parameter.
