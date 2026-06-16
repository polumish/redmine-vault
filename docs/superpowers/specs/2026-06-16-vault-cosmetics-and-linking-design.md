# Vault plugin — cosmetics + `{{pass}}` linking — design

Status: approved direction (Redmine-native clean), pending written-spec review.
Repo: `/Volumes/DATA/GIT/redmine-vault` (branch `redmine-6.1`).

## Goal

Two cosmetic planes + one linking feature for the Redmine Vault password plugin,
all "Redmine-native, compact, very neat":

1. **External** — the project Passwords list (`keys#index`).
2. **Internal** — the single-password detail/card (`keys#show`).
3. **Linking** — reference a specific password from any Redmine text via a wiki
   macro `{{pass(ID)}}`, with a toolbar button + picker in the text editor.

Plus folding in the already-deferred edit-form layout bug fix.

AES-256-GCM body encryption is **Phase 2** — documented at the end, but executed
as its **own** implementation plan (a crypto data-migration across 3 production
Redmines should not ride along with UI work).

Vaultwarden integration ("Redmine stores only references to Vaultwarden items")
is explicitly **out of scope** here — it gets its own future brainstorm. The
macro syntax is chosen to be forward-compatible with it.

## Non-goals

- No Vaultwarden/Bitwarden integration in this spec.
- No change to the encryption-at-rest of bodies in this spec (that is Phase 2).
- No change to the JSON write API surface (`docs/api-usage.md` stays valid).

## Current state (relevant facts)

- `init.rb` already registers `VaultViewHook < Redmine::Hook::ViewListener#view_layouts_base_html_head`
  injecting `vault.css` + `vault.js` on every page. **Reuse it** — no new hook needed
  for the toolbar button.
- `keys#index` (`app/views/keys/index.html.erb`) crams the search form **inside `<h2>`**
  with a deprecated `<font size="2">` tag; `Clear` is a separate `button_to` form so it
  drops to its own misaligned line.
- List rows are per-STI-type partials: `vault/passwords/_password.html.erb`,
  `vault/key_files/_key_file.html.erb` (both render `<tr>` rows). `vault/keys/_key.html.erb`
  is a separate label/value `<table>`. `keys#show` does `render @key`, so list-row and
  detail markup are **tangled**. This design untangles them.
- `vault.js` already carries a delegated copy handler (`data-clipboard-target`, commit 95f9a35).
- `vault.css` is 29 lines; most styling is inherited from Redmine core.
- Text formatting on red.half = `textile` (Redmine 6.1.2) → classic `jsToolBar`.
  **Must confirm the setting on vs-com + volia before building** the toolbar button;
  if any uses markdown/common_mark, the button needs that editor's hook too.
- Per-key access is the `whitelist` column; `Vault::Key#whitelisted?(User, project)` is
  the authority (admins and users without `whitelist_keys` perm pass).

## Plane A — Passwords list (`keys#index`)

- `<h2>` holds **only** the title (`t('key.title.list')`).
- Move the search form out of the heading into a dedicated toolbar `<div>` below it:
  `[ search 🔍 ] (•)Name ( )URL ( )Tags  [Update] [Clear]` on one line. Remove the
  `<font>` tag. Render `Update` and `Clear` as sibling buttons in the same form area so
  they align (Clear keeps its reset-the-query behaviour).
- Keep the standard Redmine `.list` table. Add a **`⧉ link`** action to each row's
  buttons column that copies `{{pass(<id>)}}` to the clipboard (see Plane C/F).
- Surface the key **`#id`** as a small muted suffix next to the name (so the macro id is
  discoverable even without the copy button).
- `New Password` stays in `.contextual` (top-right).
- Keep the popular-tags sidebar.

## Plane B — Password detail / card (`keys#show`)

Untangle list vs detail:

- List rows stay in the per-type partials (`vault/passwords/_password`,
  `vault/key_files/_key_file`). Their job: one `<tr>`.
- Introduce a dedicated **detail partial** rendered by `show.html.erb` (e.g.
  `app/views/keys/_detail.html.erb`), replacing the bare `render @key`/`vault/keys/_key`
  table. One partial handles all types (branch on `key.is_a?(Vault::KeyFile)` etc.).
- Layout = Redmine issue-style `<div class="box">` with a label:value grid:
  - Name, **#id** (visible), Login (copy), URL (link or copy), **Password**
    (masked `*****` + `👁 show/hide` toggle + `⧉ copy`, reusing the existing
    `plain_pass_<id>` + copy handler pattern), Tags (chips), Files (📄 name + comment,
    download/preview links), Comment (rendered as wiki text via `textilizable`).
- Top `.contextual` actions: **✎ Edit · ⧉ Copy · 🗑 Delete · ⧉ link** (link copies the macro).
- Permission: respect `whitelisted?` exactly as the controller already does.

## Plane C — Wiki macro `{{pass(ID)}}`

- Register in `init.rb` (or a required `lib/vault/macros.rb`) via
  `Redmine::WikiFormatting::Macros.register`. Name: **`pass`**. (Aliases optional; default
  to `pass` only per decision.)
- Args: `{{pass(42)}}` and `{{pass(42, "custom label")}}`.
- Resolution: `Vault::Key.find_by(id:)`. The key id is global, so the macro derives the
  key's project and builds `project_key_path(key.project, key)`.
- **Permission-aware (decided):**
  - viewer **has** access (`key.whitelisted?(User.current, key.project)` and module/perm
    ok) → render `🔒 <name>` (or custom label) as a link to the password.
  - viewer **lacks** access → render neutral **`🔒 (немає доступу)` / `🔒 (no access)`**,
    **no name leak**, no link.
  - key missing → `🔒 (not found)`.
- Forward-compat: keep resolution behind a small helper so a future Vaultwarden model can
  reuse the same `{{pass(...)}}` syntax pointing at a VW item id.

## Plane D — Editor toolbar button + picker

- **Picker endpoint:** new lightweight action `keys#picker` (`format: :json`,
  session-authenticated, `view_keys` perm). Returns **only** `[{id, name}]` for keys in the
  project that are visible to `User.current` (filter by `whitelisted?`). **Does NOT decrypt
  bodies** (fast + no secret exposure). Route: `GET /projects/:project_id/keys/picker`.
- **Toolbar button:** extend `vault.js` (already injected on every page) to add a button to
  Redmine's `jsToolBar` (textile). Button label/icon = 🔒, title = "Insert password link".
- **Project context:** detect the current project identifier from the page (issue form /
  breadcrumb / URL `/projects/<id>/...`). If no project context (global wiki, new issue
  before a project is chosen) → insert empty `{{pass()}}` skeleton and tooltip
  "open within a project to pick".
- **Picker UI:** clicking the button opens a small modal: search box + scrollable list of
  `🔒 <name>  #<id>` from the picker endpoint for the current project. Selecting an item
  inserts `{{pass(<id>)}}` at the cursor.
- All of this lives in `plugins/vault/` (JS in `assets/`, endpoint in the plugin
  controller) → survives Redmine core upgrades.
- **Confirm formatter on all 3 hosts first.** If markdown/common_mark is enabled anywhere,
  add that editor's insertion path too.

## Plane E — Edit-form attachments layout fix (deferred bug)

- In `app/views/keys/_form.html.erb`, the `.vault-attachments` section breaks Redmine's
  `.box.tabular` grid: rows are not indented under the input column and the per-row
  `Delete` checkbox+label overflows left outside the box.
- Fix: wrap the section as a tabular `<p>` row (label in the left column), indent attachment
  rows to the field column, style the delete control inline. Add the rules to `vault.css`.

## Plane F — "Copy link" affordance

- A reusable control (list action + card action) that copies `{{pass(<id>)}}` to the
  clipboard via the existing clipboard mechanism, with a brief "copied" tooltip.

## Data flow

- Render macro: issue text → Redmine formatter → `pass` macro → key lookup + permission
  check → link or neutral text.
- Picker: toolbar click → AJAX `GET …/keys/picker` (session) → `[{id,name}]` (whitelist
  filtered, no bodies) → modal → insert `{{pass(id)}}`.
- Copy link: click → clipboard ← `{{pass(id)}}`.

## Permissions & security

- Picker returns only id+name of whitelisted keys; never bodies.
- Macro never renders name/link to users without access.
- No secret ever enters issue text — only the `{{pass(id)}}` reference (the core security
  win; keeps secrets out of email notifications, search, REST API, and DB/issue backups).

## i18n

- New/changed labels in `config/locales/en.yml` + `ru.yml` (the maintained pair):
  `key.btn.copy_link`, `key.macro.no_access`, `key.macro.not_found`,
  `key.toolbar.insert_pass`, `key.picker.title`, `key.picker.search`, `key.attr.id`,
  `key.btn.show`/`key.btn.hide`. Other locale files left as-is (already partial).

## Testing

- Harness constraint (known): the full test suite needs `capybara-screenshot` (absent), so
  it runs in CI/prod, not the colima harness. Use `docker cp` into a Redmine-6.1+sqlite
  container for model/unit checks (as done for v0.6.0).
- Add unit coverage where pure-Ruby: macro resolution (access / no-access / missing),
  `keys#picker` returns whitelist-filtered id+name only (no body). View/JS toolbar verified
  live after deploy.

## Deploy notes (all 3 Redmines)

- JS **and** CSS change → `assets:precompile` is **required** (not just restart).
- Restart: `touch tmp/restart.txt` — ensure it is app-owned first (root-owned file makes the
  www-data touch silently fail; confirm restart via `Passenger RubyApp` lstart). Canary
  red.half, then vs-com + volia.
- Confirm `Setting.text_formatting` on vs-com + volia before relying on the textile toolbar
  path.

## Phase 2 (separate implementation plan) — AES-256-GCM body encryption

- Move `body` from the configurable cipher (default VaultCipher AES-128-ECB; often weak /
  no-op on hosts without a cipher key) to authenticated **AES-256-GCM**, reusing the
  `vendor/file_cipher.rb` approach already proven for attachments.
- Needs a data migration to re-encrypt existing `keys.body` rows on all 3 hosts; per-host DB
  backup first; dirty-guarded encrypt to avoid double-encryption (mirror the KeyFile/Attachment
  pattern). This is security-critical and gets its own spec + plan, executed immediately after
  this cosmetic/linking work.

## Forward-compatibility note (future Vaultwarden integration)

- The `{{pass(id)}}` macro and the picker are designed so the underlying target can later
  become a Vaultwarden item id (reference-only / deep-link model, "Redmine holds references,
  Vaultwarden holds secrets"). No change to the user-facing syntax expected.
