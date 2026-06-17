module Vault
  require 'csv'

  class Vault::Key < ActiveRecord::Base
    belongs_to :project
    has_and_belongs_to_many :tags, class_name: 'Vault::Tag'
    has_many :vault_attachments, class_name: 'Vault::Attachment',
             foreign_key: 'vault_key_id', dependent: :destroy

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

  end

  class Vault::KeysVaultTags < ActiveRecord::Base
  end

end
