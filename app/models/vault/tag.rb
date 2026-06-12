module Vault
  class Tag < ActiveRecord::Base
    self.table_name = 'vault_tags'
    belongs_to :project
    has_and_belongs_to_many :keys

    validates :name, presence: true, uniqueness: { scope: :project_id }

    # Parse a comma-separated string into persisted Tag records scoped to a
    # project. Null-safe and idempotent: blank/duplicate names are dropped and
    # existing tags are reused, so the result never contains nil (which would
    # raise AssociationTypeMismatch when assigned to a key's HABTM collection).
    def self.create_from_string(string, project)
      return [] if string.blank?

      names = string.downcase.split(/,\s*/).map(&:strip).reject(&:blank?).uniq
      names.map { |name| where(project_id: project.id).find_or_create_by(name: name) }
           .select(&:persisted?)
    end

    def self.tags_to_string(tags)
      return '' if tags.empty?
      tags.map(&:name).join(', ')
    end

    def self.cloud_for_project(pid)
      tags_with_score = joins(:keys).where(vault_tags: { project_id: pid })
                                    .group('vault_tags.name').count
      tags_with_score.sort_by { |_tag, count| count }.map(&:first).reverse.take(20)
    end

    def self.tags_list(pid)
      where(project_id: pid).order(:name).pluck(:name)
    end
  end
end
