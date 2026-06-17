# "Sensitive" passwords (dev/PM access split) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-password `sensitive` flag so developers read normal project passwords but not the sensitive infra/cloud ones; sensitive passwords are visible only to holders of a new `view_sensitive_keys` permission (Managers/Sysadmins/admins).

**Architecture:** New boolean column `keys.sensitive` + a capability permission `view_sensitive_keys`. One DRY predicate `Vault::Key#viewable?(project)` (= `whitelisted?` AND sensitivity-ok) gates every read site (list, show, edit, card, picker, `{{pass}}` macro). The Sensitive checkbox and the `:sensitive` strong-param are limited to permission holders. The rest is Redmine role configuration.

**Tech Stack:** Redmine 6.1 / Rails 7.2 / Ruby 3.3, MariaDB. Tests: `ActiveSupport::TestCase` / `Redmine::ControllerTest`.

**Spec:** `docs/superpowers/specs/2026-06-17-vault-sensitive-keys-design.md`

**Repo rule:** commit messages are plain Conventional Commits — **NO `Co-Authored-By` / Claude / AI mention** anywhere.

---

## Test-execution note
No runnable Redmine app in this repo (test_helper needs `capybara-screenshot`). Implementers:
write code + tests, verify with `ruby -c`; real test runs in CI / on a host. View/CSS verified
live at deploy (Task 6).

## File structure
- **Create:** `db/migrate/015_add_sensitive_to_keys.rb`, `test/unit/vault_sensitive_test.rb`,
  `test/functional/keys_sensitive_test.rb`.
- **Modify:** `init.rb` (permission + version), `app/models/vault/key.rb` (viewable?),
  `app/controllers/keys_controller.rb` (gates + key_params), `lib/vault/password_link.rb`,
  `app/views/keys/_form.html.erb` (checkbox), `app/views/shared/_key_fields.html.erb` (badge),
  `assets/stylesheets/vault.css` (badge), `config/locales/en.yml` + `ru.yml`.

---

## Task 1: Migration — `keys.sensitive` column

**Files:** Create `db/migrate/015_add_sensitive_to_keys.rb`; Test `test/unit/vault_sensitive_test.rb` (stub, expanded in Task 2).

- [ ] **Step 1: Implement the migration** — `db/migrate/015_add_sensitive_to_keys.rb`:
```ruby
class AddSensitiveToKeys < ActiveRecord::Migration[7.2]
  def change
    add_column :keys, :sensitive, :boolean, default: false, null: false
  end
end
```

- [ ] **Step 2: Verify** — `ruby -c db/migrate/015_add_sensitive_to_keys.rb` → "Syntax OK";
`grep -n 'class AddSensitiveToKeys' db/migrate/015_add_sensitive_to_keys.rb` matches.

- [ ] **Step 3: Commit**
```bash
git add db/migrate/015_add_sensitive_to_keys.rb
git commit -m "feat: add sensitive boolean column to keys"
```

---

## Task 2: Permission + `Vault::Key#viewable?` + version

**Files:** Modify `init.rb`, `app/models/vault/key.rb`; Test `test/unit/vault_sensitive_test.rb`.

- [ ] **Step 1: Write the failing test** — `test/unit/vault_sensitive_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)

class VaultSensitiveTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys)
  end

  def test_non_sensitive_is_viewable_with_view_keys
    User.current = User.find(2) # jsmith, member of project 1 via role 1
    k = Vault::Password.create!(project: @project, name: 'n1', sensitive: false)
    assert k.viewable?(@project)
  end

  def test_sensitive_hidden_without_permission
    Role.find(1).remove_permission!(:view_sensitive_keys)
    User.current = User.find(2)
    k = Vault::Password.create!(project: @project, name: 's1', sensitive: true)
    refute k.viewable?(@project)
  end

  def test_sensitive_visible_with_permission
    Role.find(1).add_permission!(:view_sensitive_keys)
    User.current = User.find(2)
    k = Vault::Password.create!(project: @project, name: 's2', sensitive: true)
    assert k.viewable?(@project)
  ensure
    Role.find(1).remove_permission!(:view_sensitive_keys)
  end

  def test_admin_sees_sensitive
    User.current = User.find(1) # admin
    k = Vault::Password.create!(project: @project, name: 's3', sensitive: true)
    assert k.viewable?(@project)
  end
end
```

- [ ] **Step 2: Run it, verify it fails** — `RAILS_ENV=test bin/rails test test/unit/vault_sensitive_test.rb`
→ FAIL (`undefined method viewable?` / unknown permission). Locally: `ruby -c test/unit/vault_sensitive_test.rb` → "Syntax OK".

- [ ] **Step 3: Add the permission** — in `init.rb`, inside the `project_module :keys do … end`
block, after the `permission :view_keys, …` line, add:
```ruby
    permission :view_sensitive_keys, {}
```

- [ ] **Step 4: Add the predicates** — in `app/models/vault/key.rb`, add these methods inside
`class Vault::Key` (e.g. right after the existing `whitelisted?` method):
```ruby
    # Combined read gate: the per-key whitelist AND the sensitivity rule.
    def viewable?(project)
      whitelisted?(User, project) && sensitivity_ok?(project)
    end

    # Non-sensitive keys are fine for anyone with view_keys; sensitive ones need
    # admin or the view_sensitive_keys permission.
    def sensitivity_ok?(project)
      return true unless sensitive?
      User.current.admin? || User.current.allowed_to?(:view_sensitive_keys, project)
    end
```

- [ ] **Step 5: Bump version** — in `init.rb` change `version '0.8.3'` → `version '0.9.0'`.
(If the current version differs, set it to `'0.9.0'` regardless.)

- [ ] **Step 6: Verify** — `ruby -c init.rb` and `ruby -c app/models/vault/key.rb` → "Syntax OK";
`grep -n view_sensitive_keys init.rb` shows the permission; `grep "version '" init.rb` → 0.9.0.
(CI/host: run the test, expect PASS.)

- [ ] **Step 7: Commit**
```bash
git add init.rb app/models/vault/key.rb test/unit/vault_sensitive_test.rb
git commit -m "feat: view_sensitive_keys permission + Key#viewable? sensitivity gate"
```

---

## Task 3: Controller gates + strong param

**Files:** Modify `app/controllers/keys_controller.rb`; Test `test/functional/keys_sensitive_test.rb`.

- [ ] **Step 1: Write the failing test** — `test/functional/keys_sensitive_test.rb`:
```ruby
require File.expand_path('../../test_helper', __FILE__)

class KeysSensitiveTest < Redmine::ControllerTest
  tests KeysController
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Role.find(1).add_permission!(:view_keys, :edit_keys)
    Setting.plugin_vault = { 'use_null_encryption' => true } # avoid the "key not set" guard
    @normal = Vault::Password.create!(project: @project, name: 'Normal', body: 'n', sensitive: false)
    @secret = Vault::Password.create!(project: @project, name: 'Secret', body: 's', sensitive: true)
  end

  def teardown
    Setting.plugin_vault = {}
  end

  def test_index_hides_sensitive_without_permission
    @request.session[:user_id] = 2 # jsmith, no view_sensitive_keys
    get :index, params: { project_id: @project.identifier }
    assert_response :success
    assert_select 'a', text: 'Normal'
    assert_select 'a', text: 'Secret', count: 0
  end

  def test_index_shows_sensitive_with_permission
    Role.find(1).add_permission!(:view_sensitive_keys)
    @request.session[:user_id] = 2
    get :index, params: { project_id: @project.identifier }
    assert_select 'a', text: 'Secret'
  ensure
    Role.find(1).remove_permission!(:view_sensitive_keys)
  end

  def test_show_sensitive_forbidden_without_permission
    @request.session[:user_id] = 2
    get :show, params: { project_id: @project.identifier, id: @secret.id }
    assert_select '#errorExplanation, .flash.error, .nodata', { minimum: 0 } # rendered an error page, not the key
    assert_select 'label#plain_pass_show_' + @secret.id.to_s, count: 0
  end

  def test_update_sensitive_param_ignored_without_permission
    @request.session[:user_id] = 2 # has edit_keys, not view_sensitive_keys
    put :update, params: { project_id: @project.identifier, id: @normal.id,
                           vault_key: { name: 'Normal', sensitive: '1' } }
    assert_equal false, Vault::Password.find(@normal.id).sensitive
  end
end
```

- [ ] **Step 2: Run it, verify it fails** — `RAILS_ENV=test bin/rails test test/functional/keys_sensitive_test.rb`
→ FAIL (sensitive key still listed / param honored). Locally: `ruby -c` the test → "Syntax OK".

- [ ] **Step 3: Swap the read gates** — in `app/controllers/keys_controller.rb`, replace
`key.whitelisted?(User, @project)` / `@key.whitelisted?(User, @project)` with the `viewable?`
gate at these five read sites:
  - `index` filter line: `@keys = @keys.select { |key| key.viewable?(@project) } unless @keys.nil?`
  - `picker`: `keys = @project.keys.order(:name).select { |k| k.viewable?(@project) }`
  - `edit`: `if !@key.viewable?(@project)`
  - `show`: `if !@key.viewable?(@project)`
  - `card`: `unless @key.viewable?(@project)`
(Keep each surrounding block — same error responses; the existing `not_whitelisted` message
"Password not allowed for you" / "Ключ вам не доступен" covers the sensitive case too.)

- [ ] **Step 4: Gate the strong param** — replace `key_params` with:
```ruby
  def key_params
    permitted = [:type, :name, :body, :login, :url, :comment]
    permitted << :sensitive if User.current.allowed_to?(:view_sensitive_keys, @project)
    params.require(:vault_key).permit(*permitted)
  end
```

- [ ] **Step 5: Verify** — `ruby -c app/controllers/keys_controller.rb` → "Syntax OK";
`grep -c 'whitelisted?(User' app/controllers/keys_controller.rb` → 0 (all five read sites now
use `viewable?`; `update_wishlist` uses `allowed_to?(:manage_whitelist_keys)`, not `whitelisted?`).
Confirm `grep -c 'viewable?(@project)' app/controllers/keys_controller.rb` → 5. (CI/host: run the test, expect PASS.)

- [ ] **Step 6: Commit**
```bash
git add app/controllers/keys_controller.rb test/functional/keys_sensitive_test.rb
git commit -m "feat: gate list/show/edit/card/picker by viewable?; sensitive param permission-gated"
```

---

## Task 4: `{{pass}}` macro respects sensitivity

**Files:** Modify `lib/vault/password_link.rb`; Test: extend `test/unit/vault_password_link_test.rb`.

- [ ] **Step 1: Add the failing test** — append to `test/unit/vault_password_link_test.rb`
(inside the existing `class VaultPasswordLinkTest`):
```ruby
  def test_no_access_for_sensitive_without_permission
    Role.find(1).add_permission!(:view_keys)
    Role.find(1).remove_permission!(:view_sensitive_keys)
    User.current = User.find(2)
    key = Vault::Password.create!(project: @project, name: 'sek', type: 'Vault::Password', sensitive: true, whitelist: '')
    assert_equal :no_access, Vault::PasswordLink.resolve(key.id)[:state]
  end
```

- [ ] **Step 2: Run it, verify it fails** — `RAILS_ENV=test bin/rails test test/unit/vault_password_link_test.rb`
→ FAIL (returns `:ok`). Locally: `ruby -c lib/vault/password_link.rb` + the test → "Syntax OK".

- [ ] **Step 3: Implement** — in `lib/vault/password_link.rb`, change the `:ok` condition from
`key.whitelisted?(User, key.project)` to `key.viewable?(key.project)`:
```ruby
      if User.current.allowed_to?(:view_keys, key.project) &&
         key.viewable?(key.project)
        { state: :ok, key: key }
```

- [ ] **Step 4: Verify** — `ruby -c lib/vault/password_link.rb` → "Syntax OK". (CI/host: run, PASS.)

- [ ] **Step 5: Commit**
```bash
git add lib/vault/password_link.rb test/unit/vault_password_link_test.rb
git commit -m "feat: {{pass}} macro hides sensitive keys from users without view_sensitive_keys"
```

---

## Task 5: Form checkbox + list badge + CSS + i18n

**Files:** Modify `app/views/keys/_form.html.erb`, `app/views/shared/_key_fields.html.erb`,
`assets/stylesheets/vault.css`, `config/locales/en.yml`, `config/locales/ru.yml`.

- [ ] **Step 1: i18n** — in `config/locales/en.yml`, under `key:` → `attr:` add:
```yaml
      sensitive: "Sensitive"
```
In `config/locales/ru.yml`, under `key:` → `attr:` add:
```yaml
      sensitive: "Чутливый"
```
Verify: `ruby -ryaml -e 'YAML.load_file("config/locales/en.yml"); YAML.load_file("config/locales/ru.yml"); puts "ok"'` → `ok`.

- [ ] **Step 2: Form checkbox** — in `app/views/keys/_form.html.erb`, immediately AFTER the
Tags paragraph:
```erb
    <p><%= f.label :tags, t('key.attr.tags') %>
    <%= f.text_field :tags, value: Vault::Tag.tags_to_string(key.tags), class: 'autocomplete' %></p>
```
insert:
```erb
    <% if User.current.allowed_to?(:view_sensitive_keys, @project) %>
      <p><%= f.label :sensitive, t('key.attr.sensitive') %>
      <%= f.check_box :sensitive %></p>
    <% end %>
```

- [ ] **Step 3: List badge** — in `app/views/shared/_key_fields.html.erb`, in the first `<td>`
(the name cell), after the `<span class="vault-id">#<%= key.id %></span>` line, add:
```erb
  <% if key.sensitive? %><span class="vault-sensitive-badge" title="<%= t('key.attr.sensitive') %>"><i class="fa fa-lock fa-fw"></i></span><% end %>
```

- [ ] **Step 4: CSS** — append to `assets/stylesheets/vault.css`:
```css
/* sensitive password badge */
.vault-sensitive-badge { color: #c61a1a; margin-left: 4px; font-size: 90%; }
```
Verify balanced braces: `ruby -e 'c=File.read("assets/stylesheets/vault.css"); abort("unbalanced") unless c.count("{")==c.count("}"); puts "ok"'` → `ok`.

- [ ] **Step 5: ERB sanity** — `ruby -e "require 'erb'; %w[app/views/keys/_form.html.erb app/views/shared/_key_fields.html.erb].each{|f| ERB.new(File.read(f), trim_mode: '-').src}; puts 'erb ok'"` → `erb ok`.

- [ ] **Step 6: Commit**
```bash
git add app/views/keys/_form.html.erb app/views/shared/_key_fields.html.erb assets/stylesheets/vault.css config/locales/en.yml config/locales/ru.yml
git commit -m "feat: Sensitive checkbox (permission-gated) + list badge + i18n"
```

---

## Task 6: Deploy + role config + verify (controller-coordinated; canary red.half → vs-com → volia)

Uses production SSH + the Vaultwarden Mac-sudo password; the controller runs it. Owners:
red.half=`www-data` `/var/www/redmine`; vs-com=`web1` `/var/www/clients/client1/web1/web`;
volia=`www-data` `/var/www/redmine`. The 🔒 badge touches `vault.css` → **assets:precompile IS required**.

- [ ] **Step 1: Merge to `redmine-6.1` + push** (after Tasks 1–5):
```bash
git checkout redmine-6.1 && git merge --no-ff feat/sensitive-keys -m "Merge: Sensitive passwords (dev/PM split, v0.9.0)"
git push origin redmine-6.1
```
Confirm no AI attribution: `git log <prev>..HEAD --format='%B' | grep -i 'co-authored\|claude\|anthropic'` → empty.

- [ ] **Step 2: Per host — deploy.**
```
git -C plugins/vault fetch origin redmine-6.1 && git -C plugins/vault reset --hard origin/redmine-6.1
sudo -u <owner> RAILS_ENV=production bin/rails runner 'puts "boot v=#{Redmine::Plugin.find(:vault).version}"'  # expect 0.9.0
sudo -u <owner> RAILS_ENV=production bin/rake redmine:plugins:migrate NAME=vault   # runs 015
sudo -u <owner> RAILS_ENV=production bin/rails assets:precompile
sudo -u <owner> touch tmp/restart.txt   # app-owned; confirm RubyApp lstart flips
```

- [ ] **Step 3: Role config (no code), each host** — via `bin/rails runner` or Admin UI:
```
# Manager: gains view_sensitive_keys, loses whitelist_keys (the misconfig that gates PMs)
Role.find_by(name: 'Manager').add_permission!(:view_sensitive_keys)
Role.find_by(name: 'Manager').remove_permission!(:whitelist_keys)
# (Sysadmin role, if any: add_permission!(:view_sensitive_keys))
# Developer stays view_keys + edit_keys (+ download/export), WITHOUT view_sensitive_keys — leave as-is.
```
(Run as `sudo -u <owner> RAILS_ENV=production bin/rails runner '<the two lines>'`.)

- [ ] **Step 4: Verify (canary red.half first).**
  - `bin/rails runner` as a non-privileged member context is hard; instead verify with SQL +
    a privileged check: column exists (`SHOW COLUMNS FROM \`keys\` LIKE 'sensitive'`), and the
    permission is registered (`Redmine::AccessControl.permission(:view_sensitive_keys).present?`).
  - Live (browser): as a **Developer** test account — the list excludes sensitive keys, opening
    a sensitive key by URL shows the error page, `{{pass(<sensitive id>)}}` renders "(no access)".
    As a **Manager** — sees all + the Sensitive checkbox on the form. HTTP 200 throughout.
  - Only after canary is clean → vs-com → volia.

- [ ] **Step 5: Data step (PM/sysadmin, post-deploy, manual).** Edit the infra/cloud passwords
  (AWS, Proxmox, Azure, …) and tick **Sensitive**. (Optional helper to bulk-tag by name/tag can
  be a follow-up; do it by hand for the known set first.)

- [ ] **Step 6: Rollback (if needed).** `migrate NAME=vault VERSION=14` (drops the column) +
  `git reset` to the 0.8.x tip + precompile + restart; revert the two role-permission changes.

---

## Self-review notes
- Spec coverage: column→Task 1; permission + viewable?/sensitivity_ok?→Task 2; controller gates
  (index/show/edit/card/picker) + key_params→Task 3; macro→Task 4; checkbox + badge + i18n→Task 5;
  role config + data step + deploy (with precompile) + verify→Task 6.
- `viewable?` / `sensitivity_ok?` / `sensitive?` / `view_sensitive_keys` / `vault-sensitive-badge`
  names are consistent across model (Task 2), controller (Task 3), macro (Task 4), views/CSS (Task 5).
- `AddSensitiveToKeys` matches `015_add_sensitive_to_keys.rb`.
- Error message reuse (`not_whitelisted`) is intentional — no new error i18n key needed.
- assets:precompile required (badge adds CSS) — stated in Task 6.
