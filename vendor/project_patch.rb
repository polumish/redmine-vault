module ProjectPatch
  def self.prepended(base)
    base.class_eval do
      has_many :keys, class_name: 'Vault::Key'
      has_many :vault_tags, class_name: 'Vault::Tag'
    end
  end
end

Project.prepend(ProjectPatch)
