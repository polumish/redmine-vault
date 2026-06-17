# Vault Password History / Field-Level Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record who changed a Vault password (and its metadata) and when, keeping every previous value viewable/copyable on the key's detail card — read-only, no rollback.

**Architecture:** A new `vault_key_versions` table stores a full snapshot of a key's *prior* state on each update that touches an audited column. Capture is a `before_update`/`after_update` pair on `Vault::Key` so all write paths (web, JSON API, console) are covered atomically. The old password body is stored as ciphertext **verbatim** (copied from `body_was`, no re-encryption). History visibility reuses `Vault::Key#viewable?`; old bodies decrypt through a shared `BodyCipher.read` helper (GCM with legacy fallback).

**Tech Stack:** Ruby on Rails (Redmine 6.1 plugin), MariaDB 11.8, AES-256-GCM (`BodyCipher`), ERB views, Minitest.

---

## Conventions for the implementer (read first)

- **Repo:** `/Volumes/DATA/GIT/redmine-vault`, branch `redmine-6.1`.
- **NO AI ATTRIBUTION** anywhere — commit messages are Conventional Commits with **no** `Co-Authored-By` / `Claude` / `Anthropic` trailers. This repo's history was scrubbed once already; do not reintroduce it.
- **MariaDB reserved word:** the keys table is `keys` (reserved). Only ActiveRecord touches it here, so no raw SQL is needed — but never write raw `JOIN keys` without `quote_table_name`.
- **Tests run in the Redmine harness, not locally.** The local checkout has no Redmine root and the full suite needs `capybara-screenshot` (absent). Run unit tests by copying the plugin into a Redmine 6.1 + sqlite container (`docker cp`) and running, from the Redmine root:
  `RAILS_ENV=test bin/rails test plugins/vault/test/unit/<file>.rb`
  Each task's "Run test" step shows that command. If the harness is unavailable, write + commit the code and tests and mark the run step as "verify in CI/prod harness".
- **Migration numbering:** next free number is **016** (015 is the last existing migration). Migration classes use `ActiveRecord::Migration[7.2]`.
- Versioning rule (standing): the final task bumps `init.rb` to **0.10.0** and adds a `CHANGELOG.md` entry. Do not bump mid-plan.

---

## File Structure

- **Create** `db/migrate/016_create_vault_key_versions.rb` — the versions table.
- **Create** `app/models/vault/key_version.rb` — `Vault::KeyVersion` model (snapshot + decrypted body).
- **Create** `test/unit/vault_key_version_test.rb` — capture-callback + model tests.
- **Modify** `vendor/body_cipher.rb` — add `BodyCipher.read` (GCM + legacy fallback) shared decode.
- **Modify** `test/unit/vault_body_cipher_test.rb` — tests for `BodyCipher.read`.
- **Modify** `app/models/vault/password.rb` — `decrypt!` delegates to `BodyCipher.read`.
- **Modify** `app/models/vault/key.rb` — `has_many :vault_key_versions` + `AUDITED_FIELDS` + `stage_version`/`write_version` callbacks.
- **Modify** `app/views/keys/_detail.html.erb` — append the "History" section.
- **Modify** `config/locales/en.yml`, `config/locales/ru.yml` — `key.history.*` labels.
- **Modify** `init.rb` (version), `CHANGELOG.md` (entry).

No JS or CSS files change (history reuses the existing global `vault.js` reveal/clipboard handlers and Redmine's `.list` table + the existing `vault-tag-chip` class), so **`assets:precompile` is NOT required** on deploy.

---

## Task 1: Shared `BodyCipher.read` decode helper

Extract the "decrypt a stored body (GCM, legacy fallback)" logic into one place so both `Vault::Password` and `Vault::KeyVersion` use it.

**Files:**
- Modify: `vendor/body_cipher.rb`
- Modify: `app/models/vault/password.rb`
- Test: `test/unit/vault_body_cipher_test.rb`

- [ ] **Step 1: Write the failing tests**

Append to `test/unit/vault_body_cipher_test.rb`, inside the `class VaultBodyCipherTest` body (before the final `end`):

```ruby
  def test_read_decrypts_gcm
    enc = BodyCipher.encrypt('hunter2')
    assert_equal 'hunter2', BodyCipher.read(enc)
  end

  def test_read_falls_back_to_legacy_for_unmarked
    legacy = Encryptor.encrypt('legacy-secret')
    refute BodyCipher.marked?(legacy), 'legacy value must not be GCM-marked'
    assert_equal 'legacy-secret', BodyCipher.read(legacy)
  end

  def test_read_passes_through_nil_and_empty
    assert_nil BodyCipher.read(nil)
    assert_equal '', BodyCipher.read('')
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run (in harness): `RAILS_ENV=test bin/rails test plugins/vault/test/unit/vault_body_cipher_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'read' for BodyCipher`.

- [ ] **Step 3: Add `BodyCipher.read`**

In `vendor/body_cipher.rb`, add this method inside the `module BodyCipher` (e.g. just after `self.decrypt`):

```ruby
  # Read a stored body to plaintext: GCM for marked values, legacy Encryptor
  # fallback for unmarked/un-migrated values or if GCM verification fails — so a
  # bad row never 500s a read. nil/empty pass through unchanged.
  def self.read(blob)
    return blob if blob.nil? || blob.to_s.empty?
    if marked?(blob)
      begin
        return decrypt(blob)
      rescue StandardError
        # corrupted / colliding marker — fall through to legacy
      end
    end
    Encryptor.decrypt(blob).to_s.force_encoding('UTF-8')
  end
```

- [ ] **Step 4: Delegate `Password#decrypt!` to it**

In `app/models/vault/password.rb`, replace the entire `decrypt!` method body with:

```ruby
    # Decrypt body on read via the shared decoder (GCM, legacy fallback).
    def decrypt!
      self.body = BodyCipher.read(self.body)
      self
    end
```

(Leave `encrypt!` unchanged.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `RAILS_ENV=test bin/rails test plugins/vault/test/unit/vault_body_cipher_test.rb`
Run: `RAILS_ENV=test bin/rails test plugins/vault/test/unit/vault_password_cipher_test.rb`
Expected: PASS (both — the second confirms the `decrypt!` delegation didn't regress).

- [ ] **Step 6: Commit**

```bash
git add vendor/body_cipher.rb app/models/vault/password.rb test/unit/vault_body_cipher_test.rb
git commit -m "refactor: add BodyCipher.read shared body decoder (GCM + legacy fallback)"
```

---

## Task 2: Migration + `Vault::KeyVersion` model

Create the table and the read-side model. No capture yet — this task just makes the schema and model exist and load.

**Files:**
- Create: `db/migrate/016_create_vault_key_versions.rb`
- Create: `app/models/vault/key_version.rb`
- Modify: `app/models/vault/key.rb` (association only)
- Test: `test/unit/vault_key_version_test.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/016_create_vault_key_versions.rb`:

```ruby
class CreateVaultKeyVersions < ActiveRecord::Migration[7.2]
  def change
    create_table :vault_key_versions do |t|
      t.belongs_to :vault_key
      t.string   :name
      t.string   :login
      t.string   :url
      t.text     :comment
      t.text     :body          # OLD ciphertext, verbatim (no re-encryption)
      t.string   :whitelist
      t.boolean  :sensitive
      t.string   :changed_fields
      t.integer  :changed_by_id
      t.datetime :changed_at
      t.timestamps
    end
    add_index :vault_key_versions, [:vault_key_id, :changed_at]
  end
end
```

- [ ] **Step 2: Write the model**

Create `app/models/vault/key_version.rb`:

```ruby
module Vault
  # An immutable snapshot of a Vault::Key's PRIOR state, captured on each update
  # that changes an audited column. `body` holds the old ciphertext verbatim.
  class KeyVersion < ActiveRecord::Base
    self.table_name = 'vault_key_versions'

    belongs_to :vault_key, class_name: 'Vault::Key'
    belongs_to :changed_by, class_name: 'User', optional: true

    # The audited columns that changed in the transition that ended this value.
    def changed_field_list
      changed_fields.to_s.split(',')
    end

    # Decrypt the snapshotted password body (GCM, legacy fallback). nil/empty -> nil.
    def decrypted_body
      return nil if body.nil? || body.to_s.empty?
      BodyCipher.read(body)
    end
  end
end
```

- [ ] **Step 3: Add the association on `Vault::Key`**

In `app/models/vault/key.rb`, immediately after the existing `has_many :vault_attachments ... dependent: :destroy` line, add:

```ruby
    has_many :vault_key_versions, class_name: 'Vault::KeyVersion',
             foreign_key: 'vault_key_id', dependent: :destroy
```

- [ ] **Step 4: Write a loading/destroy test**

Create `test/unit/vault_key_version_test.rb`:

```ruby
require File.expand_path('../../test_helper', __FILE__)

class VaultKeyVersionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    User.current = User.find(1) # admin
  end

  def test_model_and_association_load
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    assert_equal 0, k.vault_key_versions.count
    v = k.vault_key_versions.create!(name: 'n', body: BodyCipher.encrypt('old'),
                                     changed_fields: 'body', changed_at: Time.current)
    assert_equal 'old', v.decrypted_body
    assert_equal ['body'], v.changed_field_list
  end

  def test_versions_destroyed_with_key
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    v = k.vault_key_versions.create!(changed_fields: 'body', changed_at: Time.current)
    k.destroy
    assert_nil Vault::KeyVersion.find_by(id: v.id)
  end
end
```

- [ ] **Step 5: Run migration + tests**

Run (in harness, from Redmine root):
`RAILS_ENV=test bin/rails redmine:plugins:migrate NAME=vault`
then `RAILS_ENV=test bin/rails test plugins/vault/test/unit/vault_key_version_test.rb`
Expected: migration creates `vault_key_versions`; both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/016_create_vault_key_versions.rb app/models/vault/key_version.rb app/models/vault/key.rb test/unit/vault_key_version_test.rb
git commit -m "feat: vault_key_versions table + Vault::KeyVersion model"
```

---

## Task 3: Capture callbacks on `Vault::Key`

Record a version on every update that changes an audited column.

**Files:**
- Modify: `app/models/vault/key.rb`
- Test: `test/unit/vault_key_version_test.rb`

- [ ] **Step 1: Write the failing capture tests**

Append to `class VaultKeyVersionTest` (before its final `end`).

**IMPORTANT — reload before updating.** Each test reloads the key with
`Vault::Key.find(k.id)` before `update!`, to mirror the real controller (which
operates on a freshly-found record whose `body` is raw ciphertext). Updating the
just-created in-memory object would test an unrealistic state, because
`Vault::Password`'s `after_save :decrypt!` leaves the in-memory body as
plaintext. A small helper keeps this DRY:

```ruby
  # Reload as the controller would: a fresh record whose body is raw ciphertext.
  def reload_key(k)
    Vault::Key.find(k.id)
  end

  def test_no_version_on_create
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    assert_equal 0, k.vault_key_versions.count
  end

  def test_version_on_body_change_stores_old_ciphertext
    k = Vault::Password.create!(project: @project, name: 'n', body: 'old-secret')
    reload_key(k).update!(body: 'new-secret')
    assert_equal 1, k.vault_key_versions.count
    v = k.vault_key_versions.first
    assert_includes v.changed_field_list, 'body'
    assert BodyCipher.marked?(v.body), 'stored old body must be GCM ciphertext'
    refute_equal 'old-secret', v.body
    assert_equal 'old-secret', v.decrypted_body
  end

  # The key real-world case: editing only metadata while the form RESUBMITS the
  # unchanged password as plaintext must NOT record a spurious body change.
  def test_metadata_edit_resubmitting_same_body_is_not_a_body_change
    k = Vault::Password.create!(project: @project, name: 'n', login: 'old', body: 'secret')
    fresh = reload_key(k)
    fresh.assign_attributes(login: 'new', body: 'secret') # body unchanged, resubmitted
    fresh.save!
    v = k.vault_key_versions.first
    assert_equal ['login'], v.changed_field_list
    refute v.changed_field_list.include?('body'), 'unchanged password must not count'
    assert_nil v.body, 'no old password stored on a metadata-only version'
  end

  def test_version_on_metadata_change_only_lists_changed
    k = Vault::Password.create!(project: @project, name: 'n', login: 'old', url: 'http://old')
    reload_key(k).update!(login: 'new')
    v = k.vault_key_versions.first
    assert_equal ['login'], v.changed_field_list
    assert_equal 'old', v.login
  end

  def test_no_version_on_noop_save
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    reload_key(k).save!
    assert_equal 0, k.vault_key_versions.count
  end

  def test_no_version_on_tags_only_change
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    k.tags = Vault::Tag.create_from_string('alpha', @project)
    assert_equal 0, k.vault_key_versions.count
  end

  def test_records_changed_by_and_at
    k = Vault::Password.create!(project: @project, name: 'n', body: 'old')
    User.current = User.find(2)
    reload_key(k).update!(body: 'new')
    v = k.vault_key_versions.first
    assert_equal User.find(2).id, v.changed_by_id
    assert_not_nil v.changed_at
  end

  def test_keeps_all_versions
    k = Vault::Password.create!(project: @project, name: 'n', body: 'v1')
    reload_key(k).update!(body: 'v2')
    reload_key(k).update!(body: 'v3')
    assert_equal 2, k.vault_key_versions.count
    assert_equal ['v1', 'v2'], k.vault_key_versions.order(:id).map(&:decrypted_body)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `RAILS_ENV=test bin/rails test plugins/vault/test/unit/vault_key_version_test.rb`
Expected: FAIL — capture tests find 0 versions (no capture yet).

- [ ] **Step 3: Implement the capture callbacks**

In `app/models/vault/key.rb`, add the constant + callbacks. Put the `META_FIELDS` constant and the two `before_update`/`after_update` lines near the top of the `class Vault::Key` body (just after the `has_many :vault_key_versions` association added in Task 2):

```ruby
    # Metadata columns audited via ordinary dirty tracking. `body` is handled
    # separately (semantic compare) because the form resubmits it as plaintext.
    META_FIELDS = %w[name login url comment whitelist sensitive].freeze

    before_update :stage_version
    after_update  :write_version
```

Then add the methods inside the `class Vault::Key` body (e.g. after `sensitivity_ok?`, before the class's closing `end`):

```ruby
    # Snapshot the PRIOR state on update. Metadata uses dirty tracking; body is
    # compared SEMANTICALLY (old decrypted vs new decrypted) because Vault::Password
    # decrypts body in-memory and the edit form resubmits the password as plaintext
    # on every save — so a raw string diff would flag a "password change" on every
    # metadata edit. The old body is read as ciphertext straight from the DB row
    # (still the pre-UPDATE value here) and stored verbatim, only when it changed.
    def stage_version
      changed   = META_FIELDS & changed_attribute_names_to_save
      old_body  = persisted_body
      body_diff = BodyCipher.read(old_body) != BodyCipher.read(self.body)
      changed << 'body' if body_diff
      @staged_version = changed.empty? ? nil : {
        name:           name_was,
        login:          login_was,
        url:            url_was,
        comment:        comment_was,
        body:           body_diff ? old_body : nil,
        whitelist:      whitelist_was,
        sensitive:      sensitive_was,
        changed_fields: changed.join(','),
        changed_by_id:  User.current&.id,
        changed_at:     Time.current
      }
      true
    end

    # Persist the staged snapshot inside the same save transaction (key.id stable).
    def write_version
      vault_key_versions.create!(@staged_version) if @staged_version
    ensure
      @staged_version = nil
    end

    # The body as currently stored in the DB (old value, before this UPDATE).
    # Bypasses in-memory dirty state, which Vault::Password#decrypt! can leave as
    # plaintext. nil for non-password keys.
    def persisted_body
      Vault::Key.where(id: id).pick(:body)
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `RAILS_ENV=test bin/rails test plugins/vault/test/unit/vault_key_version_test.rb`
Expected: PASS (all capture tests + the Task 2 tests).

- [ ] **Step 5: Run the broader model suite (regression)**

Run: `RAILS_ENV=test bin/rails test plugins/vault/test/unit/key_test.rb plugins/vault/test/unit/vault_sensitive_test.rb plugins/vault/test/unit/vault_password_cipher_test.rb`
Expected: PASS — capture callbacks must not break existing key behavior.

- [ ] **Step 6: Commit**

```bash
git add app/models/vault/key.rb test/unit/vault_key_version_test.rb
git commit -m "feat: capture key version snapshots on audited-field updates"
```

---

## Task 4: History section on the detail card + i18n

Render the read-only history on the key's detail card, reusing the existing reveal/copy widget.

**Files:**
- Modify: `app/views/keys/_detail.html.erb`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`

- [ ] **Step 1: Add i18n labels (en)**

In `config/locales/en.yml`, under the `key:` map (e.g. after the `attachment:` block, same indentation as `attr:`/`picker:`), add:

```yaml
    history:
      title: "History"
      when: "Changed at"
      who: "By"
      changed: "Changed fields"
      values: "Previous values"
```

- [ ] **Step 2: Add i18n labels (ru)**

In `config/locales/ru.yml`, under the matching `key:` map, add:

```yaml
    history:
      title: "История"
      when: "Изменено"
      who: "Кем"
      changed: "Изменённые поля"
      values: "Прежние значения"
```

- [ ] **Step 3: Append the History section to the card**

In `app/views/keys/_detail.html.erb`, insert this block immediately **before** the final closing `</div>` (the one that closes `<div class="box vault-card">` at the end of the file, right after the comment block):

```erb
  <% versions = key.vault_key_versions.order(changed_at: :desc, id: :desc) %>
  <% if versions.any? %>
    <div class="vault-card-history">
      <h3><%= t('key.history.title') %></h3>
      <table class="list">
        <thead>
          <tr>
            <th><%= t('key.history.when') %></th>
            <th><%= t('key.history.who') %></th>
            <th><%= t('key.history.changed') %></th>
            <th><%= t('key.history.values') %></th>
          </tr>
        </thead>
        <tbody>
          <% versions.each do |v| %>
            <tr class="<%= cycle('odd', 'even') %>">
              <td><%= format_time(v.changed_at) %></td>
              <td><%= v.changed_by ? v.changed_by.name : '—' %></td>
              <td>
                <% v.changed_field_list.each do |f| %><span class="vault-tag-chip"><%= t("key.attr.#{f}", default: f) %></span> <% end %>
              </td>
              <td>
                <% if v.changed_field_list.include?('body') && v.decrypted_body.present? %>
                  <div class="vault-pass-value">
                    <label class="vault-mask">*********</label>
                    <label id="hist_pass_<%= v.id %>" style="display:none;"><%= v.decrypted_body.to_s.force_encoding('UTF-8') %></label>
                    <a href="#" class="keys-actions vault-reveal" data-target="hist_pass_<%= v.id %>" title="<%= t('key.btn.show') %>"><i class="fa fa-eye fa-fw"></i></a>
                    <a href="#" class="keys-actions" data-clipboard-target="hist_pass_<%= v.id %>" title="<%= t('key.btn.clipboard') %>"><i class="fa fa-clipboard fa-fw"></i></a>
                  </div>
                <% end %>
                <% %w[login url name comment whitelist].each do |f| %>
                  <% if v.changed_field_list.include?(f) && v.public_send(f).present? %>
                    <div><span class="vault-history-label"><%= t("key.attr.#{f}") %>:</span> <%= v.public_send(f) %></div>
                  <% end %>
                <% end %>
                <% if v.changed_field_list.include?('sensitive') %>
                  <div><span class="vault-history-label"><%= t('key.attr.sensitive') %>:</span> <%= v.sensitive ? '☑' : '☐' %></div>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>
```

Notes: `_detail` is only rendered after the controller's `viewable?` gate passes, so the history (including old bodies) is already access-protected. The reveal/clipboard anchors use the same `vault-reveal`/`data-target`/`data-clipboard-target` contract as the current-password widget, which `vault.js` binds globally via delegation — no JS change needed. The `.list` table and `vault-tag-chip` are existing styles, so no CSS change/precompile.

- [ ] **Step 4: Manual render verification (harness)**

In the harness, create a password, update its body and its login twice via the web UI (or console + reload the show page), then open the key's detail card. Expected: a "History" section appears, newest-first; the body row shows masked `*********` that reveals on 👁 click and copies on the clipboard icon; metadata rows show the prior login/url. As a non-whitelisted/over-sensitive user, the whole card (and thus history) is blocked — confirm `show` still returns the not-whitelisted error.

- [ ] **Step 5: Commit**

```bash
git add app/views/keys/_detail.html.erb config/locales/en.yml config/locales/ru.yml
git commit -m "feat: password history section on the key detail card (read-only)"
```

---

## Task 5: Version bump + CHANGELOG

**Files:**
- Modify: `init.rb`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump the version**

In `init.rb`, change the line `version '0.9.0'` to:

```ruby
  version '0.10.0'
```

- [ ] **Step 2: Add the changelog entry**

Prepend a new dated section to `CHANGELOG.md` (match the existing entry style):

```markdown
## 0.10.0 — 2026-06-17

### Added
- **Password change history / field-level audit.** Each update that changes an
  audited field (`name`, `login`, `url`, `comment`, `body`, `whitelist`,
  `sensitive`) now records an immutable snapshot of the prior state in the new
  `vault_key_versions` table (migration 016), with who changed it and when.
- **History section on the key detail card** (read-only): previous values
  newest-first; old passwords use the same masked reveal + copy widget and are
  gated by `Vault::Key#viewable?` (whitelist + sensitivity), exactly like the
  current body. No new permission.
- Old password bodies are stored as ciphertext verbatim (no re-encryption) and
  decoded via the new shared `BodyCipher.read` helper (GCM with legacy fallback).

### Notes
- Tags and attachments are **not** audited in this release (they are saved after
  the key record, outside the `before_update` capture). Deferred.
- Capture covers all write paths (web, JSON API, console); versions are kept
  indefinitely. No `assets:precompile` needed (ERB + i18n + migration only).
```

- [ ] **Step 3: Commit**

```bash
git add init.rb CHANGELOG.md
git commit -m "chore: release 0.10.0 (password history / field audit)"
```

---

## Task 6: Pre-deploy verification (harness boot check)

Confirms the plugin boots and the new pieces load before any production deploy.

**Files:** none (verification only).

- [ ] **Step 1: Full plugin unit suite in harness**

Run: `RAILS_ENV=test bin/rails test plugins/vault/test/unit`
Expected: PASS (note: any pre-existing skips for missing gems are unrelated).

- [ ] **Step 2: Boot + load check**

Run (in harness, production-like env):

```bash
RAILS_ENV=production bin/rails runner '
  Vault::KeyVersion
  raise "BodyCipher.read missing" unless BodyCipher.respond_to?(:read)
  raise "read roundtrip" unless BodyCipher.read(BodyCipher.encrypt("x")) == "x"
  raise "callbacks missing" unless Vault::Key._update_callbacks.map(&:filter).include?(:stage_version)
  puts "OK: KeyVersion loads, BodyCipher.read works, capture callback registered"
'
```

Expected: prints `OK: ...` and exits 0. (A `Zeitwerk::NameError` here means a file under `lib/`/`app/` doesn't match its constant — but `KeyVersion` lives in `app/models/vault/key_version.rb` matching `Vault::KeyVersion`, so it should load.)

- [ ] **Step 3: Confirm clean history (no AI attribution)**

Run:

```bash
git log 0ae8e05..HEAD --format='%H %an %s%n%b' | grep -iE 'co-authored|claude|anthropic' && echo 'FOUND — FIX BEFORE PUSH' || echo 'clean'
```

Expected: `clean`.

---

## Deploy (after plan execution — operator step, not a coding task)

Standard recipe, canary **red.half → vs-com → volia**. Per host (`sudo ssh -p 5022`):
1. Backup vault tables: `mysqldump … keys vault_tags keys_vault_tags vault_attachments > /root/vault-pre-0.10.0-<host>-20260617.sql` (pw via `MYSQL_PWD` from `database.yml`).
2. `git -C plugins/vault fetch origin redmine-6.1 && git -C plugins/vault reset --hard origin/redmine-6.1`.
3. **Boot check BEFORE anything else:** the `bin/rails runner` from Task 6 Step 2 (Zeitwerk/lib gotcha — run before migrate).
4. `RAILS_ENV=production bin/rake redmine:plugins:migrate NAME=vault` (applies 016).
5. **No `assets:precompile`** (no JS/CSS changed).
6. Restart: `touch tmp/restart.txt` — must be **app-owned** (if root-owned from a prior session, `touch` silently no-ops; `chown` to the app user first). Confirm via `ps -eo lstart,args | grep 'Passenger RubyApp'` flipping to ~now.
7. Verify: open a key with ≥1 change → History section renders; reveal/copy work.

Rollback: `RAILS_ENV=production bin/rake redmine:plugins:migrate NAME=vault VERSION=15` (drops `vault_key_versions`; `keys` untouched) + `git reset --hard <prev>` + restart, or restore the SQL backup.

Post-deploy: push GitHub mirror (`git push github redmine-6.1:main`), update WIKI (`/Volumes/DATA/WIKI/development/redmine-vault.md`), LightRAG, and memory.
