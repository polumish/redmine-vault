module Vault
  require 'csv'

  class Vault::Key < ActiveRecord::Base
    belongs_to :project
    has_and_belongs_to_many :tags, class_name: 'Vault::Tag'
    has_many :vault_attachments, class_name: 'Vault::Attachment',
             foreign_key: 'vault_key_id', dependent: :destroy
    has_many :vault_key_versions, class_name: 'Vault::KeyVersion',
             foreign_key: 'vault_key_id', dependent: :destroy

    # Metadata columns audited via ordinary dirty tracking. `body` is handled
    # separately (semantic compare) because the form resubmits it as plaintext.
    META_FIELDS = %w[name login url comment whitelist sensitive].freeze

    before_update :stage_version
    after_update  :write_version

    def encrypt!
      self
    end

    def decrypt!
      self
    end

    def self.import(file)
      CSV.foreach(file.path, headers:true) do |row|
        rhash = row.to_hash

				decryptb = Encryptor::decrypt(rhash['body'])

				key = Vault::Key.where("name = ?", rhash['name']).first
		
				attrs = {
					project_id: rhash['project_id'],
					name: rhash['name'],
					body: decryptb,
					login: rhash['login'],
					type: rhash['type'],
					file: rhash['file'],
					url: rhash['url'],
					comment: rhash['comment'],
					whitelist: rhash['whitelist']
				}

				begin
					if key
						Vault::Key.update(key.id, attrs)
					else
						Vault::Key.create(attrs).update_column(:id, rhash['id'])
					end
				rescue => e
					Rails.logger.warn("Vault::Key.import failed for '#{rhash['name']}': #{e.message}")
				end
      end
    end

    def whitelisted?(user,project)
      return true if user.current.admin or !user.current.allowed_to?(:whitelist_keys, project)
      self.whitelist.split(",").each do |id|
        return true if User.in_group(id).where(:id => user.current.id).count == 1
      end
      return self.whitelist.split(",").include?(user.current.id.to_s)
    end

    # Combined read gate: the per-key whitelist AND the sensitivity rule.
    def viewable?(project)
      whitelisted?(User, project) && sensitivity_ok?(project)
    end

    # Non-sensitive keys are fine for anyone with view_keys; sensitive ones need
    # admin or the view_sensitive_keys permission.
    def sensitivity_ok?(project)
      return true unless sensitive?
      User.current.admin? || User.current.allowed_to?(:view_sensitive_keys, project)
    end

    # Snapshot the PRIOR state while dirty info is available. `*_was` are the
    # persisted (old) metadata values. `body` is compared SEMANTICALLY (old
    # decrypted vs new decrypted) because Vault::Password decrypts body in-memory
    # and the edit form resubmits the password as plaintext on every save — so a
    # raw string diff would flag a "password change" on every metadata edit. The
    # old body is read as ciphertext straight from the DB row (still the pre-UPDATE
    # value here) and stored verbatim, only when it actually changed.
    def stage_version
      changed   = META_FIELDS & changed_attribute_names_to_save
      old_body  = persisted_body
      body_diff = BodyCipher.read(old_body) != BodyCipher.read(self.body)
      changed << 'body' if body_diff
      @staged_version = changed.empty? ? nil : {
        name:           name_was,
        login:          login_was,
        url:            url_was,
        comment:        comment_was,
        body:           body_diff ? old_body : nil,
        whitelist:      whitelist_was,
        sensitive:      sensitive_was,
        changed_fields: changed.join(','),
        changed_by_id:  User.current&.id,
        changed_at:     Time.current
      }
      true
    end

    # Persist the staged snapshot inside the same save transaction (key.id stable).
    def write_version
      vault_key_versions.create!(@staged_version) if @staged_version
    ensure
      @staged_version = nil
    end

    # The body as currently stored in the DB (old value, before this UPDATE).
    # Bypasses in-memory dirty state, which Vault::Password#decrypt! can leave as
    # plaintext. nil for non-password keys.
    def persisted_body
      Vault::Key.where(id: id).pick(:body)
    end

  end

  class Vault::KeysVaultTags < ActiveRecord::Base
  end

end
