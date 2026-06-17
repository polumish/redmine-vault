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

    # Decrypt body on read via the shared decoder (GCM, legacy fallback).
    def decrypt!
      self.body = BodyCipher.read(self.body)
      self
    end

  end
end
