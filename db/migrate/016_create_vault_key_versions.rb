class CreateVaultKeyVersions < ActiveRecord::Migration[7.2]
  def change
    create_table :vault_key_versions do |t|
      t.belongs_to :vault_key
      t.string   :name
      t.string   :login
      t.string   :url
      t.text     :comment
      t.text     :body          # OLD ciphertext, verbatim (no re-encryption)
      t.string   :whitelist
      t.boolean  :sensitive
      t.string   :changed_fields
      t.integer  :changed_by_id
      t.datetime :changed_at
      t.timestamps
    end
    add_index :vault_key_versions, [:vault_key_id, :changed_at]
  end
end
