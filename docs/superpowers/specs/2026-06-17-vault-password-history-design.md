# Vault — Password change history / field-level audit (v0.10.0)

## Goal

Track who changed a password (and its metadata) and when, and keep the
**previous values** so that authorized users can view and copy them. This is a
read-only audit/history feature — no rollback action.

Decided during brainstorming (2026-06-17):

- **Scope:** full field-level audit, not just the password body. Snapshot the
  prior body **and** the prior key metadata on every change.
- **Retention:** keep all versions (no auto-prune). Passwords change rarely; the
  full trail is the audit value.
- **Restore:** view/copy only. No "restore" button. To roll back, a user copies
  an old value and edits normally — which itself records a new version.
- **Access:** history reuses `Vault::Key#viewable?` — old passwords are exactly
  as sensitive as the current one (whitelist + `sensitive` flag). No new
  permission.

## Non-goals (v1)

- Auditing **tags** and **attachments**. Both are mutated *after* `@key.save` in
  the controller (`@key.tags = …`, `process_attachments(@key)`), so they are
  invisible to a `before_update` model hook. Auditing them needs separate
  association-level hooks — deferred, noted in the changelog.
- A "restore previous value" write action.
- A separate `view_key_history` permission (history == current-body
  sensitivity, gated by `viewable?`).

## Data model — `vault_key_versions` (migration 016)

One row per **update** that changes at least one audited column. Each row is a
**full snapshot of the prior (pre-change) state**, so reading history never
requires reconstructing values from diffs.

| column | type | notes |
|---|---|---|
| `vault_key_id` | bigint, indexed | FK → `keys.id` |
| `name` | string | prior value |
| `login` | string | prior value |
| `url` | string | prior value |
| `comment` | text | prior value |
| `body` | text | prior body **stored as ciphertext verbatim** (copied from `body_was`; no re-encryption — same approach as migration 012 for attachments) |
| `whitelist` | string | prior value |
| `sensitive` | boolean | prior value |
| `changed_fields` | string | CSV of audited columns that changed in the transition that *ended* this value (drives the "what changed" display) |
| `changed_by_id` | integer, nullable | `User.current.id` of who superseded this value (nullable for console / anonymous) |
| `changed_at` | datetime, indexed | when this value was superseded |

Indexes: `vault_key_id`, and `[vault_key_id, changed_at]` for newest-first
listing.

Semantics of a row: *"this value held until `changed_at`, when `changed_by`
replaced it."* The **current** value lives on the `keys` row itself; versions
hold only superseded states. Versions are created on **update only** (a freshly
created key has no prior value).

Retention: keep all. `dependent: :destroy` so deleting a key removes its history.

New model `Vault::KeyVersion` (`app/models/vault/key_version.rb`):

- `belongs_to :vault_key, class_name: 'Vault::Key'`
- `belongs_to :changed_by, class_name: 'User', optional: true`
- `decrypted_body` — decrypt `body` via the shared body decode helper (GCM,
  legacy fallback). Returns `nil`/empty for non-password keys.

`Vault::Key has_many :vault_key_versions, foreign_key: 'vault_key_id',
dependent: :destroy`.

## Capture mechanism — `before_update` on `Vault::Key`

Two paired callbacks on `Vault::Key` (inherited by all STI types). This covers
**every** write path that funnels through `@key.save`: web `create`/`update`,
the JSON API, and console edits.

Split into capture (before) + persist (after) so the snapshot reads dirty state
while it's available, but the row is written **after** the key is saved — inside
the same DB transaction, with a stable `keys.id`.

**Metadata fields** (`name login url comment whitelist sensitive`) are detected
with ordinary dirty tracking (`*_was`) — they are not transformed on save, so a
string diff is a true diff. **`body` needs special handling** (see the critical
note below): its change is detected *semantically* (old decrypted vs new
decrypted), and the old value is read as ciphertext straight from the DB.

```
META_FIELDS = %w[name login url comment whitelist sensitive]

before_update :stage_version
after_update  :write_version

# before_update: dirty info available; *_was = persisted (old) metadata values.
def stage_version
  changed   = META_FIELDS & changed_attribute_names_to_save  # dirty metadata cols
  old_body  = persisted_body                                 # raw old ciphertext from DB
  body_diff = BodyCipher.read(old_body) != BodyCipher.read(self.body)  # semantic
  changed << 'body' if body_diff
  @staged_version = changed.empty? ? nil : {
    name:           name_was,
    login:          login_was,
    url:            url_was,
    comment:        comment_was,
    body:           body_diff ? old_body : nil,  # old ciphertext, only if pw changed
    whitelist:      whitelist_was,
    sensitive:      sensitive_was,
    changed_fields: changed.join(','),
    changed_by_id:  User.current&.id,
    changed_at:     Time.current
  }
  true
end

# after_update: still inside the save transaction; key.id is stable.
def write_version
  vault_key_versions.create!(@staged_version) if @staged_version
ensure
  @staged_version = nil
end

# The body as currently stored in the DB (old value, before this UPDATE).
def persisted_body
  Vault::Key.where(id: id).pick(:body)
end
```

### CRITICAL: why body needs semantic detection (not raw dirty tracking)

`Vault::Password` has `before_save :encrypt!` / `after_save :decrypt!`, and the
**edit form pre-fills the password field with the decrypted plaintext** (`edit`
calls `decrypt!`, then `f.text_field :body`). So on *every* form submit, `body`
comes back as plaintext while the stored value is ciphertext. Naive
`body_changed?` / `changed_attribute_names_to_save` would therefore report `body`
as changed on **every edit** — even a URL-only change — producing a spurious
"password changed" version and duplicating the password each time. Comparing the
**decrypted** old and new values fixes this: a version records `body` only when
the actual secret changed.

- `persisted_body` reads the old ciphertext directly from the DB row (still the
  pre-UPDATE value inside `before_update`). This is bulletproof regardless of the
  in-memory encrypt/decrypt state — unlike `body_was`/`body_in_database`, which
  can be left holding plaintext by the after-save `decrypt!`.
- At `before_update` (after `encrypt!`), `self.body` is the new ciphertext (or
  nil for `Vault::KeyFile`); `BodyCipher.read` decrypts both sides for the
  comparison. For non-password keys both sides are nil → never a body change.
- The old body is stored **only when the password actually changed**, and always
  as ciphertext (verbatim from the DB), so the versions table never holds a
  plaintext password and metadata-only versions don't duplicate it.

Notes / correctness:

- `after_update` runs inside ActiveRecord's save transaction, so the version row
  and the key update commit (or roll back) atomically.
- The guard (`@staged_version` nil) prevents empty versions on no-op saves and
  tags-only edits (tags are HABTM, set after `@key.save`, and don't dirty the
  key row).
- `User.current` is set by Redmine in controller and API contexts; nil-safe for
  console.

## Access & decryption

- History renders only when `key.viewable?(project)` is already true — the same
  gate as the current body on the card. No new permission.
- Old-body decryption mirrors `Vault::Password#decrypt!`:
  `BodyCipher.marked?(body)` → AES-256-GCM via `BodyCipher.decrypt`; otherwise
  legacy `Encryptor.decrypt` fallback (so legacy/un-migrated ciphertext and any
  GCM-verify failure never 500 a history row).
- Extract this decode-with-fallback into a small shared helper so
  `Vault::Password` and `Vault::KeyVersion` don't duplicate it. Targeted
  cleanup only — no refactor of unrelated code.

## UI — "History" section on the detail card

Appended to `app/views/keys/_detail.html.erb`, rendered only when the key has
versions **and** `viewable?` (the partial is already reached only when
`viewable?`).

- A collapsible "History" block (`<h3>`), versions newest-first.
- Each row shows: `changed_at` · `changed_by` (user name, or "—") · badges for
  the changed fields (from `changed_fields`).
- For a body change, the prior password renders with the **same** masked
  reveal + copy widget as the current body
  (`vault-mask` / `vault-reveal` / `data-clipboard-target`, unique element id
  per version row). Decryption via `decrypted_body`.
- For other changed fields, the prior value renders inline (e.g.
  *url: `old.example.com`*, *login: `olduser`*).
- Read-only — no restore control.
- i18n: en + ru, `key.history.*` keys.

No JS changes beyond the existing delegated reveal/copy handlers in `vault.js`
(they already bind on `[data-clipboard-target]` / `.vault-reveal` globally), so
**no `assets:precompile`** is expected — ERB partial + i18n + migration only.

## Versioning, testing, deploy

- **v0.10.0** (minor feature): bump `version` in `init.rb` and prepend a dated
  `CHANGELOG.md` entry describing the new table, the capture callback, the
  history UI, and the deferred tags/attachments note. (Standing rule: no silent
  edits.)
- **Tests** — `test/unit/vault_key_version_test.rb`:
  - version created on body change; on metadata change (e.g. url/login);
  - **no** version on no-op save and on tags-only edit;
  - `changed_fields` lists exactly the changed audited columns;
  - prior body stored as ciphertext and `decrypted_body` round-trips to the
    original plaintext (GCM and legacy);
  - `changed_by_id` / `changed_at` populated;
  - `dependent: :destroy` removes versions with the key.
  - Harness caveat (as before): the full suite needs `capybara-screenshot`
    (absent locally); unit tests run in CI/prod. Verify the model + migration in
    the `docker cp` Redmine-6.1 harness.
- **Deploy** — standard recipe, canary **red.half → vs-com → volia**: vault-table
  backup → `bin/rails runner` boot check (incl. `Vault::KeyVersion` load +
  body decode round-trip) → `rake redmine:plugins:migrate NAME=vault` (016) →
  `touch tmp/restart.txt` (app-owned). Rollback: `migrate NAME=vault
  VERSION=15` (drops `vault_key_versions`; `keys` untouched) or restore the
  pre-deploy SQL backup.
- Built **subagent-driven** with per-task review; implementer subagents told
  explicitly: **no `Co-Authored-By` / AI attribution**. Re-check
  `git log <base>..HEAD` for `co-authored/claude/anthropic` before pushing.
- After verification: record in CHANGELOG + GitHub mirror
  (`git push github redmine-6.1:main`) + WIKI
  (`/Volumes/DATA/WIKI/development/redmine-vault.md`) + LightRAG + memory.
