# Vault plugin — encryption notes

The plugin stores key bodies encrypted at rest and decrypts them for display and
API responses. Three engines are selectable in *Administration → Vault*:

| Engine          | Algorithm        | Notes |
|-----------------|------------------|-------|
| `NullCipher`    | none             | plaintext in DB — testing only |
| `VaultCipher`   | **AES-128-ECB**  | **default**, weak — see below |
| `RedmineCipher` | AES-256-CBC      | Redmine's built-in ciphering, key from `config/configuration.yml` |

## Why AES-128-ECB is weak

`VaultCipher` (`vendor/vault_cipher.rb`) uses AES in **ECB** mode:

- **Deterministic** — identical plaintext blocks produce identical ciphertext, so
  repeated/structured secrets leak patterns.
- **No IV** — nothing randomises the output.
- **No authentication** — ciphertext can be tampered with undetected (no MAC/auth
  tag).
- 128-bit key only (the setting enforces exactly 16 characters).

For a password vault this is the weakest of the three options.

## Recommendation (no code change required)

Switch the default to **`RedmineCipher`** (AES-256-CBC) via the Vault settings
toggle. It reuses Redmine's database cipher key from `configuration.yml` and is
materially stronger than ECB. Re-encrypt existing rows after switching using the
plugin's `Encryptor.encrypt_all` / `decrypt_all` helpers (back up first).

## Key files

Since 0.5.2, `Vault::KeyFile` contents are stored encrypted in the database
column `keys.file_data` (never in plaintext on disk). File encryption is
**mandatory**: `Encryptor.file_engine` uses the configured cipher, but if that is
`NullCipher` it falls back to `RedmineCipher` so files are never stored in
plaintext. (This still requires Redmine's `database_cipher_key` to be set in
`config/configuration.yml` for the fallback to actually encrypt.)

## Future work (out of scope this round)

Add an authenticated `AES-256-GCM` engine (random IV + auth tag) and a migration
path. Tracked separately — not implemented in 0.5.1.
