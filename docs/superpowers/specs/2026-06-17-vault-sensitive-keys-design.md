# Vault plugin — "Sensitive" passwords (dev/PM access split) — design

Status: approved direction, pending written-spec review.
Repo: `/Volumes/DATA/GIT/redmine-vault` (branch `redmine-6.1`). Target version **0.9.0**.

## Goal

Let developers read most project passwords but **not** the sensitive infra/cloud ones
(AWS, Proxmox, Azure, …). A password can be flagged **Sensitive**; sensitive passwords are
visible only to users with a new `view_sensitive_keys` permission (Managers / Sysadmins /
Redmine admins). Everything stays role/membership-driven: a new developer added to a project
immediately reads the non-sensitive passwords; removal from the project revokes access at once.

## Background (current model)

- Access today = Redmine role permissions (`view_keys`, `edit_keys`, `manage_whitelist_keys`,
  `whitelist_keys`, `download_keys`, `export_keys`) + the per-key `whitelist` (only restricts
  users who hold `whitelist_keys`; everyone else with `view_keys` sees all keys).
- `Vault::Key#whitelisted?(user, project)` returns true for admins and for users WITHOUT
  `whitelist_keys`; otherwise it checks the key's `whitelist` CSV.
- Developer role already has `view_keys` (no `whitelist_keys`) → currently sees ALL keys. This
  feature adds the sensitive subset that developers must NOT see.

## Decision (locked)

A simple per-key boolean **`sensitive`** flag (not named categories, not tags) — YAGNI: one
"sensitive vs not" tier. Gated by a new capability permission `view_sensitive_keys`.
Developers keep `edit_keys` (they add/edit passwords) — only the sensitivity gate is new.
The existing per-key `whitelist` / `whitelist_keys` stay unchanged as a separate fine-grained
tool.

## Components

### 1. Migration `db/migrate/015_add_sensitive_to_keys.rb`
`add_column :keys, :sensitive, :boolean, default: false, null: false`. Existing keys → not
sensitive; PM/sysadmin marks the AWS/Proxmox/Azure ones afterward (data step, post-deploy).

### 2. Permission — `init.rb`
Add to the `project_module :keys` block: `permission :view_sensitive_keys, {}` (a capability
permission with no controller-action mapping — checked only via `allowed_to?`).

### 3. `Vault::Key` — single DRY visibility helper
```ruby
def viewable?(project)
  whitelisted?(User, project) && sensitivity_ok?(project)
end

def sensitivity_ok?(project)
  return true unless sensitive?
  User.current.admin? || User.current.allowed_to?(:view_sensitive_keys, project)
end
```
`whitelisted?` keeps its existing (User-class, project) calling convention; `viewable?` is the
new gate used at every read site. (`sensitive?` is the boolean column reader.)

### 4. `keys_controller`
- `index`: change the filter from `key.whitelisted?(User, @project)` to `key.viewable?(@project)`
  (the JSON `format.api` path renders the same already-filtered `@keys`, so the API is covered).
- `show` / `edit`: replace the `whitelisted?` guard with `viewable?` (sensitive key + no
  permission → `render_error t('error.key.not_sensitive')` / 403 for API).
- `picker`: filter `@project.keys.order(:name).select { |k| k.viewable?(@project) }` (devs'
  picker won't list sensitive keys).
- `key_params`: permit `:sensitive` ONLY when
  `User.current.allowed_to?(:view_sensitive_keys, @project)` (else the param is dropped, so a
  non-privileged editor of a non-sensitive key cannot set/clear the flag). Implement by
  conditionally adding `:sensitive` to the permitted list.

### 5. `Vault::PasswordLink.resolve` (the `{{pass}}` macro)
After finding the key, gate with `viewable?` instead of just `whitelisted?` so a developer who
references a sensitive key via `{{pass(id)}}` gets the neutral "(no access)" rendering.

### 6. Views
- `app/views/keys/_form.html.erb`: a "Sensitive" checkbox (`f.check_box :sensitive`), rendered
  ONLY when `User.current.allowed_to?(:view_sensitive_keys, @project)` (or admin).
- List (`shared/_key_fields` or the per-type row) and detail card (`_detail`): a small 🔒
  "Sensitive" badge next to the name when `key.sensitive?` (only ever seen by users who can
  view the key anyway).

### 7. i18n (`config/locales/en.yml` + `ru.yml`)
`key.attr.sensitive` ("Sensitive" / "Чутливий"), `error.key.not_sensitive`
("This password is restricted" / "Цей пароль обмежено").

## Data flow
- Read (list/show/picker/macro): `viewable?` = whitelisted AND (not sensitive OR
  admin/`view_sensitive_keys`). One predicate, used everywhere.
- Write: the Sensitive checkbox is submitted only by privileged editors; `key_params` ignores
  the flag from anyone else (preserving the stored value).

## Error handling
- A non-privileged user hitting a sensitive key's show/edit URL directly → `render_error`
  (HTML) / 403 (API). They never see it in the list, picker, or macro.
- New keys default to `sensitive=false`.

## Testing (CI/prod; harness needs capybara-screenshot to load test_helper)
- `test/unit/vault_sensitive_test.rb`:
  - `viewable?` true for a non-sensitive key with `view_keys`; false for a sensitive key
    without `view_sensitive_keys`; true for a sensitive key WITH `view_sensitive_keys`; true
    for admin regardless.
  - `key_params`-style: a non-privileged update does not change `sensitive`; a privileged
    update sets it. (Functional/controller test.)
  - `Vault::PasswordLink.resolve` returns `:no_access` for a sensitive key when the user lacks
    `view_sensitive_keys`.

## Deploy (canary red.half → vs-com → volia)
- The 🔒 badge adds a rule to `vault.css`, so **`assets:precompile` IS required** this time.
  Per host: DB backup → `git reset` → boot-check → `rake redmine:plugins:migrate NAME=vault`
  (runs 015) → `assets:precompile` → restart (touch `tmp/restart.txt`, app-owned).
- **Role config (no code), all 3 hosts:** add `view_sensitive_keys` to the **Manager** role
  (and any "Sysadmin" role); **remove `whitelist_keys` from Manager** (existing misconfig — it
  currently gates non-admin PMs to whitelisted keys only). Leave **Developer** as `view_keys`
  + `edit_keys` (+ download/export), WITHOUT `view_sensitive_keys`.
- **Data step (PM/sysadmin, post-deploy):** mark the sensitive passwords (AWS / Proxmox /
  Azure / other infra accounts) with the new checkbox.
- Verify: a developer (test account / role) sees the list WITHOUT sensitive keys, cannot open a
  sensitive key by URL, and `{{pass(sensitive_id)}}` shows "(no access)"; a Manager sees all.

## Out of scope (separate next brainstorm)
- **Password change history / versioning** (who/when changed, previous values) — its own spec;
  version access will reuse this `viewable?` gate.
- Named categories / multiple sensitivity tiers (YAGNI for now).
- Removing the dormant legacy cipher guard (tracked separately).
