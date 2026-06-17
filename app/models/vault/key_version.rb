module Vault
  # An immutable snapshot of a Vault::Key's PRIOR state, captured on each update
  # that changes an audited column. `body` holds the old ciphertext verbatim.
  class KeyVersion < ActiveRecord::Base
    self.table_name = 'vault_key_versions'

    belongs_to :vault_key, class_name: 'Vault::Key'
    belongs_to :changed_by, class_name: 'User', optional: true

    # The audited columns that changed in the transition that ended this value.
    def changed_field_list
      changed_fields.to_s.split(',')
    end

    # Decrypt the snapshotted password body (GCM, legacy fallback). nil/empty -> nil.
    def decrypted_body
      return nil if body.nil? || body.to_s.empty?
      BodyCipher.read(body)
    end
  end
end
