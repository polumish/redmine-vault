# Vault — password & key manager for Redmine (fork)

![Redmine 6.1](https://img.shields.io/badge/Redmine-6.1-b1361e?logo=redmine&logoColor=white)
![Ruby 3.3](https://img.shields.io/badge/Ruby-3.3-cc342d?logo=ruby&logoColor=white)
![Version 0.5.3](https://img.shields.io/badge/version-0.5.3-1f6feb)
![Database](https://img.shields.io/badge/db-MySQL%20%7C%20MariaDB%20%7C%20PostgreSQL-336791)

Store passwords, keys, secret notes and key files **per project** inside Redmine,
with encryption, tags, per-user access control, PDF export and a JSON API.

> ### 🍴 This is a fork
> A maintained fork of the original **[noshutdown-ru/vault](https://github.com/noshutdown-ru/vault)**
> ([project page](https://noshutdown.ru/en/redmine-plugins-vault/)) by **noshutdown.ru**.
>
> The upstream plugin targets Redmine ≤ 4.2. **This fork brings it up to date for
> Redmine 6.1** (Ruby 3.3, Rails 7.2, the propshaft asset pipeline) and adds the
> features listed below.
>
> All credit for the original plugin goes to its authors. This fork keeps the
> original's license and links back to upstream.

---

## What this fork adds

Compared to upstream `0.4.3`:

- **Redmine 6.1 compatibility** — runs on Ruby 3.3 / Rails 7.2 and the modern
  asset pipeline; replaces the obsolete ZeroClipboard copy mechanism with a
  self-contained clipboard handler (the Password / Login / URL copy buttons each
  copy their own field).
- **Encrypted key files in the database** — uploaded key files are stored in an
  encrypted column instead of plaintext on disk, with a dedicated always-on
  cipher (`FileCipher`, AES-256-GCM, key derived from Redmine's `secret_key_base`).
- **Per-project tags** — tags are scoped to a project, so identical tag names no
  longer collide between clients.
- **JSON write API** — create / update / destroy keys with a Redmine API key
  (no web session or CSRF workaround). File upload & download also accept an API
  key. See [`docs/api-usage.md`](docs/api-usage.md).
- **File preview** — images and documents attached to a key open in a modal preview.
- **Per-user access (whitelist)** — restrict each key to specific users or groups.
- Numerous bug fixes (tags HTTP 500, double-encryption on partial API updates,
  import writing to the wrong column, copy-button copying the wrong field).

See [`CHANGELOG.md`](CHANGELOG.md) for the full history and
[`docs/encryption.md`](docs/encryption.md) for notes on the cipher options.

## Compatibility

| Redmine | Ruby | Rails | Databases |
|--------:|:----:|:-----:|:----------|
| **6.1** | 3.3  | 7.2   | MySQL / MariaDB / PostgreSQL |

> For older Redmine (≤ 4.2) use the original
> [noshutdown-ru/vault](https://github.com/noshutdown-ru/vault).

## Installation

```bash
cd redmine/plugins
git clone https://github.com/polumish/redmine-vault.git vault
cd ..

# install deps and run the plugin migrations
bundle install --without development test
RAILS_ENV=production bin/rails redmine:plugins:migrate NAME=vault

# Redmine 6.1 serves plugin assets through the digest pipeline — recompile them
RAILS_ENV=production bin/rails assets:precompile

touch tmp/restart.txt
```

Then enable the **Vault** module in *Project → Settings → Modules*, and grant the
`view_keys` / `edit_keys` permissions to the relevant roles.

## Configuration (encryption)

Open *Administration → Plugins → Vault → Configure* and either:

- enter a **16-character encryption key** in the plugin settings, **or**
- enable **Use Redmine Encryption** and set `database_cipher_key` in
  `config/configuration.yml`.

Key **files** are always encrypted independently with `FileCipher` regardless of
this setting. See [`docs/encryption.md`](docs/encryption.md).

## API

Manage keys with a Redmine API key — full reference in
[`docs/api-usage.md`](docs/api-usage.md):

```bash
curl -H "X-Redmine-API-Key: <key>" \
     -H "Content-Type: application/json" \
     -X POST https://redmine.example.com/projects/<id>/keys.json \
     -d '{"vault_key":{"name":"db root","login":"root","body":"s3cret","tags":["db"]}}'
```

## Development & releases

- **Development** happens on our GitLab:
  <https://git.half.net.ua/polumish/redmine-vault> (branch `redmine-6.1`).
- **Tagged releases** are published here on GitHub.

## Credits & license

- Original plugin: **[noshutdown-ru/vault](https://github.com/noshutdown-ru/vault)**
  by [noshutdown.ru](https://noshutdown.ru/en/redmine-plugins-vault/).
- This fork is distributed under the same license as the original plugin.
