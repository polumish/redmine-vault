class AddProjectToTags < ActiveRecord::Migration[4.2]
  def up
    add_column :vault_tags, :project_id, :integer unless column_exists?(:vault_tags, :project_id)

    # Backfill: attribute each existing tag to the project of its first linked
    # key. Tag names were globally unique before this migration, so scoping them
    # per project cannot create (project_id, name) collisions.
    execute <<-SQL.squish
      UPDATE vault_tags
      SET project_id = (
        SELECT keys.project_id
        FROM keys_vault_tags
        JOIN keys ON keys.id = keys_vault_tags.key_id
        WHERE keys_vault_tags.tag_id = vault_tags.id
        ORDER BY keys.project_id
        LIMIT 1
      )
      WHERE project_id IS NULL
    SQL

    add_index :vault_tags, [:project_id, :name], unique: true, name: 'index_vault_tags_on_project_id_and_name'
  end

  def down
    remove_index :vault_tags, name: 'index_vault_tags_on_project_id_and_name' if index_exists?(:vault_tags, [:project_id, :name], name: 'index_vault_tags_on_project_id_and_name')
    remove_column :vault_tags, :project_id if column_exists?(:vault_tags, :project_id)
  end
end
