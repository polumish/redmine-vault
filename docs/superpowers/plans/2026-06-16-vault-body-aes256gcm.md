# AES-256-GCM Password-Body Encryption — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encrypt `Vault::Password#body` with authenticated AES-256-GCM (key from `secret_key_base`), migrate all existing rows on the 3 Redmines, with a dormant legacy-read guard so no password can 500.

**Architecture:** New `BodyCipher` module mirrors the proven `FileCipher` but prepends a version marker (`vgcm1:`) so values are self-identifying. `Vault::Password#encrypt!` always writes GCM; `#decrypt!` reads GCM for marked values and falls back to the legacy `Encryptor` for unmarked/failed ones. Migration 013 re-encrypts legacy rows (idempotent, per-row rescue). The old `Encryptor`/cipher settings stay to power the guard, the migration's decrypt, and `down`.

**Tech Stack:** Redmine 6.1 / Rails 7.2 / Ruby 3.3, OpenSSL AES-256-GCM, MariaDB. Tests: `ActiveSupport::TestCase`.

**Spec:** `docs/superpowers/specs/2026-06-16-vault-body-aes256gcm-design.md`

---

## Test-execution note

This repo is the plugin source only — there is no runnable Redmine app here, so the Redmine
test suite cannot run locally (and `test_helper` needs `capybara-screenshot`). Implementer
subagents: write the code + tests and verify with `ruby -c` (syntax). The real verification
is in Task 5 on a host: a `bin/rails runner` cipher round-trip, the migration on canary, and a
SQL check that every body is marked + sample plaintexts match. The committed unit tests run in
CI/prod.

## File structure

**Create:**
- `vendor/body_cipher.rb` — `BodyCipher` (AES-256-GCM + marker). One responsibility: body crypto.
- `db/migrate/013_reencrypt_bodies_gcm.rb` — one-time legacy→GCM migration.
- `test/unit/vault_body_cipher_test.rb`
- `test/unit/vault_password_cipher_test.rb`
- `test/unit/vault_body_migration_test.rb`

**Modify:**
- `init.rb` — `require` body_cipher (after file_cipher); bump version `0.7.0` → `0.8.0`.
- `app/models/vault/password.rb` — rewrite `encrypt!`/`decrypt!`.

---

## Task 1: `BodyCipher`

**Files:**
- Create: `vendor/body_cipher.rb`
- Modify: `init.rb`
- Test: `test/unit/vault_body_cipher_test.rb`

- [ ] **Step 1: Write the failing test** — `test/unit/vault_body_cipher_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)

class VaultBodyCipherTest < ActiveSupport::TestCase
  def test_round_trip
    %w[hunter2 пароль123 a].each do |p|
      enc = BodyCipher.encrypt(p)
      assert BodyCipher.marked?(enc), "encrypt output must be marked"
      refute_equal p, enc
      assert_equal p, BodyCipher.decrypt(enc)
    end
  end

  def test_round_trip_long_and_utf8
    p = ('Ключ-' * 500) + "\u{1F510}"
    assert_equal p, BodyCipher.decrypt(BodyCipher.encrypt(p))
  end

  def test_marked_is_false_for_plaintext_legacy_base64_and_nil
    refute BodyCipher.marked?('hunter2')
    refute BodyCipher.marked?(Base64.strict_encode64('whatever'))
    refute BodyCipher.marked?(nil)
  end

  def test_nil_passthrough
    assert_nil BodyCipher.encrypt(nil)
  end

  def test_tamper_detection_raises
    enc = BodyCipher.encrypt('secret-value')
    raw = Base64.strict_decode64(enc[BodyCipher::MARKER.length..])
    raw[-1] = (raw[-1].ord ^ 0xFF).chr
    tampered = BodyCipher::MARKER + Base64.strict_encode64(raw)
    assert_raises(OpenSSL::Cipher::CipherError) { BodyCipher.decrypt(tampered) }
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run (Redmine test env): `RAILS_ENV=test bin/rails test test/unit/vault_body_cipher_test.rb`
Expected: FAIL — `uninitialized constant BodyCipher`. (Locally, no Redmine app: instead run `ruby -c test/unit/vault_body_cipher_test.rb` → "Syntax OK"; real run happens in CI/host.)

- [ ] **Step 3: Implement** — `vendor/body_cipher.rb`:
```ruby
require 'openssl'
require 'base64'

# Always-on authenticated encryption for password bodies (Vault::Password#body).
# Mirrors FileCipher but prepends a version MARKER so stored values are
# self-identifying — this lets reads fall back to the legacy Encryptor for
# un-migrated rows and lets the migration be idempotent. Key is derived from
# Redmine's secret_key_base (on disk, NOT in the DB dump), domain-separated from
# the file key. AES-256-GCM gives confidentiality + an auth tag (tamper detection).
module BodyCipher
  ALGORITHM = 'aes-256-gcm'.freeze
  IV_LEN    = 12
  TAG_LEN   = 16
  MARKER    = 'vgcm1:'.freeze

  # plaintext -> "vgcm1:" + base64(iv + auth_tag + ciphertext). nil passes through.
  def self.encrypt(data)
    return data if data.nil?
    cipher = OpenSSL::Cipher.new(ALGORITHM)
    cipher.encrypt
    cipher.key = key
    iv  = cipher.random_iv
    enc = cipher.update(data.to_s) + cipher.final
    MARKER + Base64.strict_encode64(iv + cipher.auth_tag + enc)
  end

  # True only for our own ciphertext (starts with MARKER).
  def self.marked?(blob)
    blob.is_a?(String) && blob.start_with?(MARKER)
  end

  # Decrypt a marked blob -> UTF-8 plaintext. Raises on tamper / wrong key / bad format.
  def self.decrypt(blob)
    raw = Base64.strict_decode64(blob.to_s[MARKER.length..] || '')
    iv  = raw[0, IV_LEN]
    tag = raw[IV_LEN, TAG_LEN]
    enc = raw[(IV_LEN + TAG_LEN)..] || ''.b
    cipher = OpenSSL::Cipher.new(ALGORITHM)
    cipher.decrypt
    cipher.key = key
    cipher.iv = iv
    cipher.auth_tag = tag
    (cipher.update(enc) + cipher.final).force_encoding('UTF-8')
  end

  def self.key
    secret = Rails.application.secret_key_base.to_s
    OpenSSL::Digest::SHA256.digest("redmine-vault:body-cipher:#{secret}")
  end
end
```

- [ ] **Step 4: Require it in `init.rb`** — add immediately AFTER the line
`require File.expand_path('vendor/file_cipher', __dir__)`:
```ruby
require File.expand_path('vendor/body_cipher', __dir__)
```

- [ ] **Step 5: Verify** — `ruby -c vendor/body_cipher.rb` → "Syntax OK"; `ruby -c init.rb` →
"Syntax OK"; `grep -n body_cipher init.rb` shows the require after file_cipher. (Run the unit
test in CI/host: expect PASS.)

- [ ] **Step 6: Commit**
```bash
git add vendor/body_cipher.rb test/unit/vault_body_cipher_test.rb init.rb
git commit -m "feat: BodyCipher (AES-256-GCM, versioned) for password bodies"
```

---

## Task 2: `Vault::Password#encrypt!` / `#decrypt!`

**Files:**
- Modify: `app/models/vault/password.rb`
- Test: `test/unit/vault_password_cipher_test.rb`

- [ ] **Step 1: Write the failing test** — `test/unit/vault_password_cipher_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)

class VaultPasswordCipherTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
  end

  def raw_body(id)
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.select_value("SELECT body FROM #{t} WHERE id=#{id.to_i}")
  end

  def test_body_stored_encrypted_and_marked
    k = Vault::Password.create!(project: @project, name: 'p1', body: 'hunter2')
    assert BodyCipher.marked?(raw_body(k.id)), 'stored body must be GCM-marked'
    refute_equal 'hunter2', raw_body(k.id)
  end

  def test_decrypt_returns_plaintext
    k = Vault::Password.create!(project: @project, name: 'p2', body: 's3cr3t')
    r = Vault::Password.find(k.id)
    r.decrypt!
    assert_equal 's3cr3t', r.body
  end

  def test_encrypt_skips_already_marked
    marked = BodyCipher.encrypt('zzz')
    k = Vault::Password.new(project: @project, name: 'p5')
    k.body = marked
    k.encrypt!
    assert_equal marked, k.body, 'already-marked value must not be re-encrypted'
    assert_equal 'zzz', BodyCipher.decrypt(k.body)
  end

  def test_decrypt_falls_back_to_legacy_for_unmarked
    Setting.plugin_vault = { 'use_null_encryption' => true } # legacy engine = passthrough
    k = Vault::Password.create!(project: @project, name: 'p3', body: 'x')
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.execute("UPDATE #{t} SET body='legacy-plain' WHERE id=#{k.id}")
    r = Vault::Password.find(k.id)
    r.decrypt!
    assert_equal 'legacy-plain', r.body
  ensure
    Setting.plugin_vault = {}
  end

  def test_blank_body_stays_blank
    k = Vault::Password.create!(project: @project, name: 'p6', body: '')
    assert_equal '', raw_body(k.id).to_s
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `RAILS_ENV=test bin/rails test test/unit/vault_password_cipher_test.rb`
Expected: FAIL — body stored via the old `Encryptor` is not `BodyCipher.marked?`. (Locally:
`ruby -c test/unit/vault_password_cipher_test.rb` → "Syntax OK".)

- [ ] **Step 3: Implement** — replace the body of `app/models/vault/password.rb` with:
```ruby
module Vault
  class Password < Key

    before_save :encrypt!
    after_save :decrypt!

    # Encrypt body with AES-256-GCM (BodyCipher) on write. Dirty-guarded so a partial
    # update that omits body cannot re-encrypt, and the marked-guard prevents
    # double-encrypting an already-encrypted value.
    def encrypt!
      if body_changed? && !self.body.nil? && !self.body.to_s.empty? && !BodyCipher.marked?(self.body)
        self.body = BodyCipher.encrypt(self.body)
      end
      self
    end

    # Decrypt body on read. GCM for marked values; fall back to the legacy Encryptor
    # for unmarked (un-migrated) values, or if GCM verification fails — so no row 500s.
    def decrypt!
      return self if self.body.nil? || self.body.to_s.empty?
      if BodyCipher.marked?(self.body)
        begin
          self.body = BodyCipher.decrypt(self.body)
          return self
        rescue StandardError
          # corrupted/colliding marker — fall through to the legacy path
        end
      end
      self.body = Encryptor::decrypt(self.body).to_s.force_encoding('UTF-8')
      self
    end

  end
end
```

- [ ] **Step 4: Verify** — `ruby -c app/models/vault/password.rb` → "Syntax OK". (CI/host: run
the test, expect PASS.)

- [ ] **Step 5: Commit**
```bash
git add app/models/vault/password.rb test/unit/vault_password_cipher_test.rb
git commit -m "feat: Vault::Password body uses BodyCipher GCM with legacy-read fallback"
```

---

## Task 3: Migration 013 (legacy → GCM)

**Files:**
- Create: `db/migrate/013_reencrypt_bodies_gcm.rb`
- Test: `test/unit/vault_body_migration_test.rb`

- [ ] **Step 1: Write the failing test** — `test/unit/vault_body_migration_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)
require File.expand_path('../../../db/migrate/013_reencrypt_bodies_gcm', __FILE__)

class VaultBodyMigrationTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Setting.plugin_vault = { 'use_null_encryption' => true } # legacy engine = passthrough
  end

  def teardown
    Setting.plugin_vault = {}
  end

  def raw_body(id)
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.select_value("SELECT body FROM #{t} WHERE id=#{id.to_i}")
  end

  def test_migrates_legacy_unmarked_row
    k = Vault::Password.create!(project: @project, name: 'm1', body: 'x')
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.execute("UPDATE #{t} SET body='plain-secret' WHERE id=#{k.id}")
    ReencryptBodiesGcm.new.up
    assert BodyCipher.marked?(raw_body(k.id))
    assert_equal 'plain-secret', BodyCipher.decrypt(raw_body(k.id))
  end

  def test_idempotent_skips_already_marked
    k = Vault::Password.create!(project: @project, name: 'm2', body: 'abc') # already GCM
    before = raw_body(k.id)
    ReencryptBodiesGcm.new.up
    assert_equal before, raw_body(k.id), 'already-marked row must be untouched'
  end
end
```

- [ ] **Step 2: Run it, verify it fails**

Run: `RAILS_ENV=test bin/rails test test/unit/vault_body_migration_test.rb`
Expected: FAIL — `uninitialized constant ReencryptBodiesGcm`. (Locally: `ruby -c` the test
file → "Syntax OK".)

- [ ] **Step 3: Implement** — `db/migrate/013_reencrypt_bodies_gcm.rb`:
```ruby
class ReencryptBodiesGcm < ActiveRecord::Migration[7.2]
  def up
    Vault::Password.reset_column_information
    migrated = 0
    skipped  = 0
    say_with_time 're-encrypt password bodies with AES-256-GCM' do
      Vault::Password.where.not(body: [nil, '']).find_each do |p|
        raw = p.read_attribute(:body)
        if BodyCipher.marked?(raw)
          skipped += 1
          next
        end
        begin
          plaintext = Encryptor.decrypt(raw)
          p.update_column(:body, BodyCipher.encrypt(plaintext))
          migrated += 1
        rescue StandardError => e
          Rails.logger.warn("vault 013: re-encrypt failed for key #{p.id}: #{e.class} #{e.message}")
          skipped += 1
        end
      end
      "migrated=#{migrated} skipped=#{skipped}"
    end
  end

  def down
    Vault::Password.reset_column_information
    say_with_time 'revert password bodies to the legacy cipher' do
      reverted = 0
      Vault::Password.where.not(body: [nil, '']).find_each do |p|
        raw = p.read_attribute(:body)
        next unless BodyCipher.marked?(raw)
        begin
          plaintext = BodyCipher.decrypt(raw)
          p.update_column(:body, Encryptor.encrypt(plaintext))
          reverted += 1
        rescue StandardError => e
          Rails.logger.warn("vault 013 down: revert failed for key #{p.id}: #{e.class} #{e.message}")
        end
      end
      "reverted=#{reverted}"
    end
  end
end
```

- [ ] **Step 4: Verify** — `ruby -c db/migrate/013_reencrypt_bodies_gcm.rb` → "Syntax OK".
(CI/host: run the migration test, expect PASS.)

- [ ] **Step 5: Commit**
```bash
git add db/migrate/013_reencrypt_bodies_gcm.rb test/unit/vault_body_migration_test.rb
git commit -m "feat: migration 013 re-encrypts password bodies to AES-256-GCM (idempotent)"
```

---

## Task 4: Version bump

**Files:**
- Modify: `init.rb`

- [ ] **Step 1: Bump version** in `init.rb`: change `version '0.7.0'` → `version '0.8.0'`.

- [ ] **Step 2: Verify** — `ruby -c init.rb` → "Syntax OK"; `grep "version '" init.rb` shows 0.8.0.

- [ ] **Step 3: Commit**
```bash
git add init.rb
git commit -m "chore: bump version to 0.8.0"
```

---

## Task 5: Deploy + verify (controller-coordinated; canary red.half → vs-com → volia)

This task uses production SSH + the Vaultwarden Mac-sudo password; the controller runs it (not
a subagent). Hosts/owners: red.half=`www-data` `/var/www/redmine`; vs-com=`web1`
`/var/www/clients/client1/web1/web`; volia=`www-data` `/var/www/redmine`.

- [ ] **Step 1: PREREQUISITE — back up `secret_key_base` of all 3 hosts to Vaultwarden.**
  Per host: `sudo -u <owner> RAILS_ENV=production bin/rails runner 'print Rails.application.secret_key_base'`
  (also confirm it is stored in `config/secrets.yml`/credentials and stable, not regenerated on
  restart). Store each value via the `vw` wrapper in the `infrastructure` folder
  (e.g. item `red.half secret_key_base`, hidden field). **Do not proceed** for a host whose key
  looks ephemeral. Reason: this key now also decrypts password bodies (it already decrypts
  attachment files).

- [ ] **Step 2: Push the branch** (after Tasks 1–4 merged to `redmine-6.1`):
```bash
git push origin redmine-6.1
```

- [ ] **Step 3: Per host — back up DB + capture sample plaintexts BEFORE.**
```
mysqldump … keys > /root/vault-pre-0.8.0-<host>-20260616.sql
# capture a few (id -> plaintext) to compare after:
sudo -u <owner> RAILS_ENV=production bin/rails runner '
  Vault::Password.where.not(body:[nil,""]).limit(3).each { |p| p.decrypt!; puts "#{p.id}\t#{p.body}" }'
```

- [ ] **Step 4: Per host — deploy (NO assets:precompile; Ruby-only change).**
```
git -C plugins/vault fetch origin redmine-6.1 && git -C plugins/vault reset --hard origin/redmine-6.1
# BOOT check BEFORE migrating/restart (Zeitwerk lesson):
sudo -u <owner> RAILS_ENV=production bin/rails runner 'puts "boot ok v=#{Redmine::Plugin.find(:vault).version}; rt=#{BodyCipher.decrypt(BodyCipher.encrypt("x"))=="x"}"'
# expect: boot ok v=0.8.0; rt=true
sudo -u <owner> RAILS_ENV=production bin/rake redmine:plugins:migrate NAME=vault
# expect migration 013 line: migrated=N skipped=M
sudo -u <owner> touch tmp/restart.txt   # ensure app-owned; confirm RubyApp lstart flips
```

- [ ] **Step 5: Per host — verify.**
```
# 1) every non-empty body is now GCM-marked (expect 0):
sudo -u <owner> RAILS_ENV=production bin/rails runner '
  t=Vault::Key.connection.quote_table_name("keys")
  n=Vault::Key.connection.select_value("SELECT COUNT(*) FROM #{t} WHERE type=\"Vault::Password\" AND body IS NOT NULL AND body<>\"\" AND body NOT LIKE \"vgcm1:%\"")
  puts "unmarked_remaining=#{n}"'
# 2) the sample ids from Step 3 still decrypt to the SAME plaintext:
sudo -u <owner> RAILS_ENV=production bin/rails runner '
  [<ids>].each { |i| p=Vault::Password.find(i); p.decrypt!; puts "#{i}\t#{p.body}" }'
# 3) site responds:
curl -s -o /dev/null -w "%{http_code}\n" https://<host>/login   # 200
```
Canary red.half first; only after `unmarked_remaining=0` + samples match + a live UI spot-check
(open a password card, reveal/copy) proceed to vs-com then volia.

- [ ] **Step 6: Rollback (only if verify fails).** `migrate NAME=vault VERSION=12` (runs 013
`down`, reverts to legacy) OR restore `/root/vault-pre-0.8.0-<host>-*.sql`; then
`git -C plugins/vault reset --hard 0ee0703`-era tag for 0.7.0 + restart.

---

## Self-review notes
- Spec coverage: BodyCipher→Task 1; encrypt!/decrypt! + guard→Task 2; migration 013 (idempotent,
  per-row rescue, down)→Task 3; version→Task 4; secret_key_base backup + per-host migrate +
  verify + no-precompile→Task 5. Out-of-scope (guard removal, settings removal, key rotation)
  correctly omitted.
- Marker `vgcm1:` and `BodyCipher.marked?`/`MARKER` are consistent across BodyCipher (Task 1),
  the model (Task 2), the migration (Task 3), and the deploy SQL check (Task 5, `body LIKE
  'vgcm1:%'`).
- `ReencryptBodiesGcm` class name matches the file `013_reencrypt_bodies_gcm.rb` (Redmine plugin
  migration convention) and is referenced identically in Task 3's test.
- No `assets:precompile` anywhere (Ruby-only change) — explicitly noted in Task 5.
