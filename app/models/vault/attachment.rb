module Vault
  # A file attached to a Vault::Key. Multiple per key, each with an optional comment.
  # Bytes are stored encrypted (AES-256-GCM via FileCipher) in `file_data`.
  class Attachment < ActiveRecord::Base
    self.table_name = 'vault_attachments'

    belongs_to :key, class_name: 'Vault::Key', foreign_key: 'vault_key_id'

    before_save :encrypt_data!

    # Encrypt the bytes only when freshly assigned this request, so a comment-only
    # update does not re-encrypt the already-ciphertext value.
    def encrypt_data!
      if file_data_changed? && !file_data.nil?
        self.file_data = FileCipher.encrypt(file_data)
      end
      self
    end

    # Decrypted file bytes, or nil if empty.
    def decrypt_data
      return nil if file_data.nil?
      FileCipher.decrypt(file_data)
    end

    # Assign an uploaded file (ActionDispatch::Http::UploadedFile): keep the original
    # name and the raw bytes (encrypted on save).
    def upload=(uploaded)
      return unless uploaded.respond_to?(:read)
      self.filename = uploaded.original_filename
      self.file_data = uploaded.read
    end

    def display_name
      filename.presence || "file ##{id}"
    end
  end
end
