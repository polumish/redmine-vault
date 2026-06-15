class CreateVaultAttachments < ActiveRecord::Migration[7.2]
  def up
    create_table :vault_attachments do |t|
      t.integer :vault_key_id, null: false
      t.string  :filename
      t.binary  :file_data, limit: 16.megabytes
      t.text    :comment
      t.timestamps
    end
    add_index :vault_attachments, :vault_key_id

    # Carry each key's existing single attached file (already FileCipher-encrypted)
    # over as its first attachment. The ciphertext is copied verbatim — same cipher,
    # so NO re-encryption. `keys` is a reserved word in MariaDB, so quote the table.
    say_with_time 'migrate existing key files into vault_attachments' do
      execute(<<~SQL.squish)
        INSERT INTO vault_attachments (vault_key_id, filename, file_data, created_at, updated_at)
        SELECT id, file, file_data, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM #{quote_table_name('keys')}
        WHERE file_data IS NOT NULL
      SQL
    end
  end

  def down
    drop_table :vault_attachments
  end
end
