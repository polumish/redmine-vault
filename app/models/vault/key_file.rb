module Vault
  class KeyFile < Key
    # File contents live in the encrypted `file_data` column (no longer on disk).
    # The `file` column holds the original filename for download.
    before_save :encrypt_file!

    # Encrypt only when a new file was assigned this request (dirty), so a
    # name-only update does not re-encrypt the already-ciphertext value.
    def encrypt_file!
      if file_data_changed? && !file_data.nil?
        self.file_data = FileCipher.encrypt(file_data)
      end
      self
    end

    # Non-mutating reader: returns the decrypted file bytes (or nil).
    def decrypt_file
      return nil if file_data.nil?
      FileCipher.decrypt(file_data)
    end

    # Assign an uploaded file (ActionDispatch::Http::UploadedFile): store the
    # original name and the raw bytes (encrypted on save).
    def upload=(uploaded)
      return unless uploaded.respond_to?(:read)
      self.file = uploaded.original_filename
      self.file_data = uploaded.read
    end
  end
end
