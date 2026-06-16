class WidenBodyAndFinishGcm < ActiveRecord::Migration[7.2]
  # Repair migration: hosts that ran an earlier 013 (before it widened `body`)
  # left long-bodied rows under the legacy cipher because GCM ciphertext overflowed
  # varchar(255). Widen the column, then re-encrypt any still-legacy (unmarked) rows.
  # Idempotent + a no-op on hosts where 013 already widened + fully migrated.
  def up
    change_column :keys, :body, :text
    Vault::Password.reset_column_information
    fixed = 0
    say_with_time 'widen body + re-encrypt any remaining legacy password bodies' do
      Vault::Password.where.not(body: [nil, '']).find_each do |p|
        raw = p.read_attribute(:body)
        next if BodyCipher.marked?(raw)
        begin
          plaintext = Encryptor.decrypt(raw)
          p.update_column(:body, BodyCipher.encrypt(plaintext))
          fixed += 1
        rescue StandardError => e
          Rails.logger.warn("vault 014: re-encrypt failed for key #{p.id}: #{e.class} #{e.message}")
        end
      end
      "fixed=#{fixed}"
    end
  end

  def down
    # No-op: the column stays `text` (shrinking could truncate legacy ciphertext);
    # body re-encryption is reverted by 013's down.
  end
end
