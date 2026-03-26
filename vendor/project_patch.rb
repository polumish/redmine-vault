module ProjectPatch
  def self.prepended(base)
    base.class_eval do
      has_many :keys, class_name: 'Vault::Key'
    end
  end
end

Project.prepend(ProjectPatch)
