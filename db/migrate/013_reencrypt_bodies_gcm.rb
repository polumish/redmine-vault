class ReencryptBodiesGcm < ActiveRecord::Migration[7.2]
  def up
    # GCM ciphertext (iv+tag+base64+marker) is ~33% + 34 bytes larger than the
    # plaintext, so a varchar(255) body overflows for longer values. Widen first.
    change_column :keys, :body, :text
    Vault::Password.reset_column_information
    migrated = 0
    skipped  = 0
    say_with_time 're-encrypt password bodies with AES-256-GCM' do
      Vault::Password.where.not(body: [nil, '']).find_each do |p|
        raw = p.read_attribute(:body)
        if BodyCipher.marked?(raw)
          skipped += 1
          next
        end
        begin
          plaintext = Encryptor.decrypt(raw)
          p.update_column(:body, BodyCipher.encrypt(plaintext))
          migrated += 1
        rescue StandardError => e
          Rails.logger.warn("vault 013: re-encrypt failed for key #{p.id}: #{e.class} #{e.message}")
          skipped += 1
        end
      end
      "migrated=#{migrated} skipped=#{skipped}"
    end
  end

  def down
    Vault::Password.reset_column_information
    say_with_time 'revert password bodies to the legacy cipher' do
      reverted = 0
      Vault::Password.where.not(body: [nil, '']).find_each do |p|
        raw = p.read_attribute(:body)
        next unless BodyCipher.marked?(raw)
        begin
          plaintext = BodyCipher.decrypt(raw)
          p.update_column(:body, Encryptor.encrypt(plaintext))
          reverted += 1
        rescue StandardError => e
          Rails.logger.warn("vault 013 down: revert failed for key #{p.id}: #{e.class} #{e.message}")
        end
      end
      "reverted=#{reverted}"
    end
  end
end
