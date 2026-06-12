class StoreKeyFilesInDb < ActiveRecord::Migration[4.2]
  def up
    unless column_exists?(:keys, :file_data)
      add_column :keys, :file_data, :binary, limit: 16.megabytes
    end

    # Move any existing on-disk key files into the encrypted DB column.
    # update_columns bypasses callbacks, so encrypt explicitly via Encryptor.
    say_with_time 'migrate on-disk key files into encrypted file_data' do
      Vault::KeyFile.reset_column_information
      migrated = 0
      Vault::KeyFile.where.not(file: [nil, '']).find_each do |kf|
        path = File.join(Vault::KEYFILES_DIR, kf.file.to_s)
        next unless File.file?(path)
        content = File.binread(path)
        kf.update_columns(
          file_data: FileCipher.encrypt(content),
          file: (kf.name.presence || kf.file)
        )
        migrated += 1
      end
      migrated
    end
  end

  def down
    remove_column :keys, :file_data if column_exists?(:keys, :file_data)
  end
end
