module Vault
  class Password < Key

    before_save :encrypt!
    after_save :decrypt!

    # Encrypt only when body was (re)assigned this request, so a partial update
    # that does not resend body (e.g. via the API) cannot double-encrypt it.
    def encrypt!
      self.body = Encryptor::encrypt(self.body) if body_changed? && !self.body.nil?
      self
    end

    #TODO: all data should be stored in UTF-8
    def decrypt!
      self.body = Encryptor::decrypt(self.body).force_encoding('UTF-8') unless self.body.nil?
      self
    end

  end
end
