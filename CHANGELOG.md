## Version: 0.8.3 (16.06.2026)
### UI
- Passwords **list**: clicking a password row (or its name / eye icon) now opens the
  password **card in a modal** instead of navigating to the full card page — same
  behaviour as the `{{pass}}` macro on issues/wiki. Real controls in the row (url
  link, login/password copy, edit/clone/delete/copy-link, checkbox) keep their own
  action. The full card page stays reachable as a no-JS fallback.
- Stored **URLs** (the key's `url`, on the card and the list) now open in a **new tab**
  (`target=_blank`, `rel=noopener`).

## Version: 0.8.2 (16.06.2026)
### UI
- `{{pass}}` card modal polish: the modal now opens **at the click point** (just above
  the cursor, clamped on-screen, re-anchored after the card loads) instead of screen
  centre — fewer mouse moves. The close **×** moved **inside** the box (no longer
  clipped by the box overflow) and highlights red on hover. The backdrop is darker
  (0.78) to better separate the card from the page.

## Version: 0.8.1 (16.06.2026)
### Features
- The `{{pass(ID)}}` link now opens the password **card in a modal overlay** on the
  same page (masked body with reveal/copy, login, url, tags, attachments, comment)
  instead of navigating to the card page — so reading a password from a wiki article
  or issue no longer loses your place. New session-auth `keys#card` endpoint renders
  the existing `_detail` partial, guarded by `whitelisted?` (403 otherwise). The macro
  keeps its `href` as a no-JS fallback. ESC / × / click-outside close the modal.

## Version: 0.8.0 (16.06.2026)
### Security
- Password bodies are now encrypted with authenticated **AES-256-GCM** (`BodyCipher`,
  key derived from Redmine's `secret_key_base` — on disk, not in the DB dump), replacing
  the weak configurable cipher (AES-128-ECB, often effectively plaintext when no key was
  set). Stored values carry a version marker (`vgcm1:`).
- Migration 013 re-encrypts all existing bodies (idempotent, per-row resilient) and widens
  `keys.body` to `text` first (GCM ciphertext is ~33% + 34 bytes larger than the plaintext,
  so it overflowed the old `varchar(255)`). Migration 014 repairs hosts that ran an earlier
  013 by widening + finishing any rows skipped due to the overflow.
- Reads fall back to the legacy cipher for any not-yet-migrated value, so nothing 500s during
  the transition. The legacy cipher and its settings are retained for that fallback and for
  rollback (`down`).

## Version: 0.7.0 (16.06.2026)
### Features
- Wiki macro `{{pass(ID)}}` (and `{{pass(ID, "label")}}`) links to a password from
  any Redmine text (issues, comments, wiki). Permission-aware: shows the name + link
  to users on the key's whitelist, a neutral "(no access)" otherwise.
- Editor toolbar button: a lock button on the text-formatting toolbar opens a picker
  of the project's accessible passwords and inserts `{{pass(ID)}}` at the cursor.
  New lightweight `keys#picker` JSON endpoint (id + name only, no decrypted bodies).
- The single-password page is redesigned as a Redmine-native card: masked password
  with reveal/copy, tag chips, attachments, and a rendered comment. Reached via an eye
  icon (or the name) in the list.
- "Copy link" action copies the `{{pass(ID)}}` macro to the clipboard.
### UI
- Passwords list: clean search toolbar (moved out of the heading), left-aligned text
  columns, right-aligned actions, monospace login/url/password, visible id, zebra rows.
- Edit form: two-column layout (fields | comment + access list), more compact; the
  access list is wrapped in a tidy, width-constrained card.
- The "Attached files" edit section is aligned within the tabular form.
### Bugfixes
- Editor/macro lock icon loads Font Awesome on every page, not just the plugin's pages.
- The single-password reveal toggle works (the assets/JS are no longer double-loaded).

## Version: 0.6.1 (15.06.2026)
### Bugfixes
- The key form is `multipart/form-data` again, so attached files actually upload.
  (The new multi-file inputs used `file_field_tag`, which — unlike the form builder's
  `file_field` — does not auto-enable multipart, so only the filename was submitted.)

## Version: 0.6.0 (15.06.2026)
### Features
- Multiple files can be attached to a key, each with its own comment, on any key type
  (including a plain `Vault::Password`). New `vault_attachments` table; bytes are
  encrypted (AES-256-GCM). Migration 012 carries each key's existing single file over
  as its first attachment (ciphertext copied verbatim, no re-encryption).
- New `KeyAttachmentsController` (download/preview by id, project-scoped, API-key
  capable). Form and show views list and manage multiple attachments.

## Version: 0.5.3 (12.06.2026)
### Security
- Key files are encrypted with a dedicated always-on cipher (`FileCipher`,
  AES-256-GCM, key derived from Redmine's `secret_key_base`) instead of the
  configurable body cipher. This guarantees encryption even when the body cipher
  is unconfigured/Null, fixes plaintext-at-rest, and preserves binary content
  (no newline stripping). Key is on disk, not in the DB dump.

## Version: 0.5.2 (12.06.2026)
### Security / Features
- Key files (`Vault::KeyFile`) are now stored **encrypted in the database**
  (`keys.file_data`), not in plaintext on disk. (Encryption hardened in 0.5.3.)
- Download/preview now serve the decrypted bytes from the DB and accept a Redmine
  API key (`accept_api_auth`). Migration 011 moves any existing on-disk files into
  the encrypted column; disk copies are removed on deploy (backed up first).
### Bugfixes
- `Vault::Password#encrypt!` is dirty-guarded so a partial API update that omits
  `body` no longer double-encrypts it.

## Version: 0.5.1 (12.06.2026)
### Bugfixes
- Fixed HTTP 500 when adding tags — `Vault::Tag.create_from_string` is now
  null-safe and idempotent (blank/duplicate names dropped, existing tags reused).
- `Vault::Key.import` wrote the comment value into the whitelist column; now reads
  the correct field and logs failures instead of silently swallowing them.
### Features
- Tags are now scoped per project (no more name collisions between clients).
- JSON write API: `create`/`update`/`destroy` accept a Redmine API key, so keys can
  be managed without the web session + CSRF workaround. Tags accept a string or an
  array. See `docs/api-usage.md`.
### Notes
- Documented the AES-128-ECB weakness of the default cipher — see
  `docs/encryption.md`.

## Version: 0.4.3 (10.05.2021)
### Bugfix
- [Saving settings path](https://github.com/noshutdown-ru/vault/pull/67)
- Fixed saving settings if key empty

## Version: 0.4.2 (10.05.2021)
### Improvements
- Added support of Redmine 4.2.1.stable, tested on 2.7.3-p183
- Updated English translation Keys changed to Passwords
- Error handling for Encryption Key (VaultEencryption) now must be exact 16 symbols

## Version: 0.4.1 (04.01.2020)
### Improvements
- [Redmine 4.1 compatibility.](https://github.com/noshutdown-ru/vault/issues/57)
- Added CHANGELOG.md

## Version: 0.4.0 (22.12.2019)
### Features
- [Get keys from project by api call.](https://github.com/noshutdown-ru/vault/pull/54) `http --json GET http://redmine.server/projects/test1/keys.json key=...`
### Improvements
- [Added validation of encryption key length.](https://github.com/noshutdown-ru/vault/pull/49)
- [Updated Portuguese - Brazil translation.](https://github.com/noshutdown-ru/vault/pull/50)
- Added Japanese translation.
- Added French translation.
- [Import from backup update existing keys by name instead of create new ones.](https://github.com/noshutdown-ru/vault/pull/53)
- [Whitelists support groups.](https://github.com/noshutdown-ru/vault/pull/51)
### Bugfixes                   
- [Export keys not working on Windows.](https://github.com/noshutdown-ru/vault/pull/52)
- [Error in redmine subdir icons display.](https://github.com/noshutdown-ru/vault/pull/47)

## Version: 0.3.11 (10.02.2019)
### Improvements
- [Support Redmine 4.0.* .](https://github.com/noshutdown-ru/vault/pull/45)
### Bugfixes 
- [Menu admin no icon.](https://github.com/noshutdown-ru/vault/issues/46)

## Version: 0.3.10 (10.12.2018)
### Improvements
- [Added Spanish translation.](https://github.com/noshutdown-ru/vault/pull/42)
### Bugfixes
- [Whitelist cannot be modifyed.](https://github.com/noshutdown-ru/vault/issues/41)
- [Redmine encryption, password cannot be longer 32 characters.](https://github.com/noshutdown-ru/vault/issues/43)

## Version: 0.3.9 (23.05.2018)
### Bugfixes
- [Incompatible character encodings.](https://github.com/noshutdown-ru/vault/issues/37)

## Version: 0.3.8 (21.05.2018)
### Improvements
- [Added German translation.](https://github.com/noshutdown-ru/vault/pull/33)
- [Added Portugal translation.](https://github.com/noshutdown-ru/vault/pull/26)
### Bugfixes
- [Double icon.](https://github.com/noshutdown-ru/vault/pull/31)
- [Copy to clipboard.](https://github.com/noshutdown-ru/vault/issues/28)

## Version: 0.3.7 (20.02.2018)
### Bugfixes 
- [Search not working.](https://github.com/noshutdown-ru/vault/issues/24)

## Version: 0.3.6 (13.02.2018)
### Bugfixes 
- [Undefined method 'offset'.](https://github.com/noshutdown-ru/vault/issues/23)

## Version: 0.3.5 (06.02.2018)
### Bugfixes
- [White lists not block user by direct link.](https://github.com/noshutdown-ru/vault/issues/22)
## Version: 0.3.4 (17.01.2018)
- [Error on searching by Name/URL (PostgreSQL).](https://github.com/noshutdown-ru/vault/issues/13) 
- [Right click no url (Redmine 3.4).](https://github.com/noshutdown-ru/vault/issues/17)

## Version: 0.3.3 (19.10.2017)
### Improvements
- Updated Chinese translation.

## Version: 0.3.2 (17.09.2017)
### Features
- Added support Redmine 3.4 .
- Added copy by click on the fields: url, login.
- Added China translation. 
- Added Dutch translation.
- Added Italian translation.
### Bugfixes
- Fixed error uploading small files.

## Version: 0.3.1 (11.12.2016)
### Bugfixes
- Edit whitelists problem.

## Version: 0.3.0 (07.12.2016)
### Features
- Added separation of access rights for users (whitelist).
- Supports Redmine 3.3 .
- Supports PostgreSQL.
- Added context menu to the list of keys.
### Improvements
- Improved mechanism for creating backups: added tags.
- http/https url open in new tabs.
### Deprecated
- Supports Redmine 2.6 terminated.

## Version: 0.2.0 (08.07/2016)
### Features
- Added ability to search by Name, URL, Tag.
- Added auto-complete for tags.
- Added functionality of creating backup copies of keys (no tags).
- Supports Redmine 3.2 .

## Version: 0.1.2 (27.02.2016)
### Features
- Added the ability to attach any file.
- Added the ability to copy to the clipboard, each key field.
### Improvements
- Improved user interface display tags.
- Improved key list display interface.
### Bugfixes
- Fixed an issue when you add a key file.

## Version: 0.1.0 (18.01.2016)
### Improvements
- Update version.

## Version: 0.0.6 (31.12.2015)
### Features
- Added the ability to specify a tag to the keys.
- Added preview mode key card (without editing).
- Added the ability to encrypt through redmine (database_cipher_key).
### Improvements
- Code refactoring.

## Version: 0.0.5 (01.11.2015)
### Features
- Added pagination.
- Added ability to sort the keys by name.
- Added a more flexible system of separation of access rights by role.
- Added the ability to clone a key (it helps to create the same type of keys).
- Added ability to print a list of passwords to PDF.
### Improvements
- Updated field at the keys: Name, URL, User Name, Password, Comment.

## Version: 0.0.4 (01.10.2015)
### Features
- Adding ssh keys file.
### Improvements
- Updated design.
- Separation of access by role.
- Compatible with Redmine 2.6 .

## Version: 0.0.3 (02.09.2015)
### Improvements
- Compatible with Ruby 1.9.1 .

## Version: 0.0.2 (01.09.2015)
### Features
- Delete keys.
- Encryption keys.

## Version: 0.0.1 (20.08.2015)
### Features
- Support Redmine 3.1.0.stable.
- Support Ruby 2.2.2-p95,2.0.0-p598.
- Support Rails 4.2.3 .
- Support Database: SQLite, MySQL.
- Support OS: Linux, OS X, Windows.
- Support Browsers: Chrome, Safari, Internet Explorer, Firefox.
- Storage of keys for each project.
- Search keys.
- Adding keys.
- Edit keys.
- Saving the key to the clipboard.