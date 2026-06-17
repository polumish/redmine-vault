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

  def self.key
    secret = Rails.application.secret_key_base.to_s
    OpenSSL::Digest::SHA256.digest("redmine-vault:body-cipher:#{secret}")
  end
end
