require 'openssl'
require 'base64'

# Always-on authenticated encryption for key-file contents. Unlike the
# configurable body cipher (Encryptor), files are ALWAYS encrypted regardless of
# plugin settings. The key is derived from Redmine's secret_key_base — present in
# every install and kept on disk (config), not in the database — so a DB dump
# alone cannot decrypt stored files. AES-256-GCM gives confidentiality + an auth
# tag (tamper detection). Binary-safe: no newline stripping, no forced encoding.
module FileCipher
  ALGORITHM = 'aes-256-gcm'.freeze
  IV_LEN    = 12
  TAG_LEN   = 16

  def self.encrypt(data)
    return data if data.nil?
    cipher = OpenSSL::Cipher.new(ALGORITHM)
    cipher.encrypt
    cipher.key = key
    iv  = cipher.random_iv
    enc = cipher.update(data) + cipher.final
    Base64.strict_encode64(iv + cipher.auth_tag + enc)
  end

  def self.decrypt(blob)
    return blob if blob.nil?
    raw = Base64.strict_decode64(blob)
    iv  = raw[0, IV_LEN]
    tag = raw[IV_LEN, TAG_LEN]
    enc = raw[(IV_LEN + TAG_LEN)..] || ''.b
    cipher = OpenSSL::Cipher.new(ALGORITHM)
    cipher.decrypt
    cipher.key = key
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.update(enc) + cipher.final
  end

  def self.key
    secret = Rails.application.secret_key_base.to_s
    OpenSSL::Digest::SHA256.digest("redmine-vault:file-cipher:#{secret}")
  end
end
