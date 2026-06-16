# Vault plugin — AES-256-GCM password-body encryption — design

Status: approved direction, pending written-spec review.
Repo: `/Volumes/DATA/GIT/redmine-vault` (branch `redmine-6.1`). Target version **0.8.0**.

## Goal

Move the password `body` from the weak/configurable cipher to authenticated
**AES-256-GCM**, reusing the proven `FileCipher` approach. One-way migration of all
existing rows on the 3 production Redmines, with a dormant legacy-read guard so no
password can become a 500 during/after the transition.

## Background (current state)

- `Vault::Password#encrypt!` (before_save) / `#decrypt!` (after_save) call `Encryptor`.
- `Encryptor.engine` picks per plugin settings: `VaultCipher` (**AES-128-ECB**, key =
  `Setting.plugin_vault['encryption_key']`; **returns plaintext if the key is blank**),
  `RedmineCipher` (Redmine::Ciphering, AES-256-CBC via `database_cipher_key`), or
  `NullCipher` (passthrough). So each host's bodies are encrypted with whatever is
  configured there — sometimes effectively plaintext.
- `FileCipher` (attachments, since v0.5.3) is the model to copy: AES-256-GCM, key =
  `SHA256("redmine-vault:file-cipher:" + secret_key_base)`, output =
  `base64(iv[12] + auth_tag[16] + ciphertext)`. Key is on disk (not in the DB dump).

## Key decisions (locked)

1. **Key source = `secret_key_base`** (domain-separated: `"redmine-vault:body-cipher:"`,
   distinct from the file key). On disk, not in DB dump, zero config, consistent with files.
   - **Risk + mitigation:** `secret_key_base` is already the single point of failure (sessions
     + attachment files depend on it). Safeguards (mandatory): back up each host's
     `secret_key_base` to Vaultwarden (infrastructure folder); document "never regenerate it";
     per-host DB backup before the migration. These are deploy prerequisites, not code.
2. **Approach B — full GCM + dormant legacy-read guard.** All writes are GCM. Migration
   converts all existing rows. `decrypt!` reads GCM for marked values and falls back to the
   legacy `Encryptor` for unmarked (or on GCM failure) so a missed/late row never 500s. After
   all 3 hosts verify 100% migrated, the guard can be removed in a later minor release.

## Components

### `vendor/body_cipher.rb` — `BodyCipher`
Mirror of `FileCipher`, with a version marker so values are self-identifying.
- `ALGORITHM = 'aes-256-gcm'`, `IV_LEN = 12`, `TAG_LEN = 16`, `MARKER = 'vgcm1:'`.
- `key` = `OpenSSL::Digest::SHA256.digest("redmine-vault:body-cipher:#{secret_key_base}")`.
- `encrypt(text)` → `MARKER + base64(iv + tag + ct)` (returns text unchanged if nil; blank
  string handled by caller). Always marked.
- `marked?(blob)` → `blob.is_a?(String) && blob.start_with?(MARKER)`.
- `decrypt(blob)` → strips `MARKER`, base64-decodes, AES-256-GCM decrypts (auth tag verified;
  raises on tamper/wrong key). Caller handles the rescue→legacy path.

### `app/models/vault/password.rb`
- `encrypt!` (before_save): `self.body = BodyCipher.encrypt(body) if body_changed? &&
  !body.nil? && !body.to_s.empty? && !BodyCipher.marked?(body)`. (Dirty-guard preserved;
  never double-encrypt an already-marked value; blank stays blank.)
- `decrypt!` (after_save + controller show/edit/index): 
  - blank/nil → return as-is.
  - `BodyCipher.marked?(body)` → `self.body = BodyCipher.decrypt(body)`, rescue → fall through
    to legacy.
  - else (unmarked) or on GCM-decrypt failure → `self.body = Encryptor.decrypt(body)` (legacy,
    host's configured cipher). Force UTF-8 as today.
  - This is the dormant guard: after full migration there are no unmarked rows.

### `db/migrate/013_reencrypt_bodies_gcm.rb`
- `up`: `Vault::Password.reset_column_information`; iterate `Vault::Password.where.not(body:
  [nil, ''])`; per row, skip if `BodyCipher.marked?(body)`; else
  `plaintext = Encryptor.decrypt(body)` (legacy, current host cipher) then
  `update_column(:body, BodyCipher.encrypt(plaintext))` (bypasses callbacks). Wrap each row in
  `begin/rescue` → `Rails.logger.warn` + skip on failure (row stays legacy, read via guard).
  `say_with_time` reports migrated / skipped counts.
- `down`: best-effort reverse — for each marked row, `plaintext = BodyCipher.decrypt(body)`
  then `update_column(:body, Encryptor.encrypt(plaintext))`. Documented primary rollback =
  restore the per-host DB backup + revert the plugin.

### Unchanged / retained
`Encryptor` + `VaultCipher`/`RedmineCipher`/`NullCipher` + the plugin's encryption settings
stay — they power the legacy-read guard, the migration's decrypt, and `down`. The settings UI
becomes vestigial for new data but is left in place (no removal now).

## Data flow
- Write (create/update a password): `encrypt!` → `BodyCipher.encrypt` → `MARKER+base64(...)`
  stored in `keys.body`.
- Read (show/edit/list): `decrypt!` → marked → `BodyCipher.decrypt`; unmarked/legacy →
  `Encryptor.decrypt`.
- Migration: legacy `keys.body` → `Encryptor.decrypt` → `BodyCipher.encrypt` → marked.

## Error handling
- GCM auth-tag failure on a marked value (corruption or marker collision with a legacy
  plaintext) → caught, falls back to legacy `Encryptor.decrypt`; if that also fails the raw
  value is returned (never a 500).
- Migration per-row failure → logged + skipped; the row remains legacy and readable via the guard.
- Blank/nil bodies are never encrypted.

## Testing (run in CI/prod; harness needs `capybara-screenshot` to load test_helper)
- `test/unit/vault_body_cipher_test.rb`: round-trip (`decrypt(encrypt(x)) == x`) incl. UTF-8 and
  long text; `marked?` true for encrypt output, false for plaintext/legacy-base64; tamper →
  decrypt raises; nil passthrough.
- `test/unit/vault_password_cipher_test.rb`: `encrypt!` marks + is dirty-guarded + does not
  double-encrypt a marked value; `decrypt!` reads a GCM value; `decrypt!` falls back for an
  unmarked legacy value; blank stays blank.
- `test/unit/vault_body_migration_test.rb` (or a functional/migration test): a legacy row
  becomes marked + decrypts to the original; an already-marked row is skipped (idempotent
  re-run); blank rows untouched.

## Deploy (canary red.half → vs-com → volia)
- **Prerequisite (do first):** read each host's `secret_key_base`, store in Vaultwarden
  (infrastructure), and confirm it is persisted (config/secrets.yml or credentials) and stable
  across restarts. Abort if a host has an ephemeral/regenerated key.
- Per host (boot-check BEFORE touching anything live, per the Zeitwerk lesson):
  1. DB backup: `mysqldump … keys > /root/vault-pre-0.8.0-<host>-<date>.sql`.
  2. Capture a few sample decrypted bodies (key id → plaintext) BEFORE, for post-verify.
  3. `git -C plugins/vault fetch origin redmine-6.1 && reset --hard origin/redmine-6.1`.
  4. `bin/rails runner` BOOT check (plugin loads, version 0.8.0).
  5. `RAILS_ENV=production bin/rake redmine:plugins:migrate NAME=vault` (runs 013).
  6. `touch tmp/restart.txt` (ensure app-owned; confirm RubyApp restart via lstart).
  - **No `assets:precompile`** — changes are Ruby-only (no JS/CSS).
- Verify per host: every `Vault::Password` body is now marked (`SELECT count(*) … body NOT LIKE
  'vgcm1:%' AND body<>''` → 0); the sample keys decrypt to the same plaintext captured in step 2.

## Out of scope
- Removing the legacy guard / old cipher / settings (separate later minor release once all
  hosts verified 100% GCM).
- Re-keying / key rotation tooling.
- Multi-address fields and Vaultwarden integration (separate brainstorms).
