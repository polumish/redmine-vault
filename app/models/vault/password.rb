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
