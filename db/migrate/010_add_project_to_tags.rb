class AddProjectToTags < ActiveRecord::Migration[4.2]
  INDEX_NAME = 'index_vault_tags_on_project_id_and_name'.freeze

  def up
    add_column :vault_tags, :project_id, :integer unless column_exists?(:vault_tags, :project_id)

    # Backfill in Ruby so it works on MySQL/MariaDB and PostgreSQL alike.
    # `keys` is a reserved word in MariaDB, so it must go through
    # quote_table_name. Each tag is attributed to the lowest project_id among
    # its linked keys; names were globally unique before this migration, so
    # scoping per project cannot create (project_id, name) collisions.
    say_with_time 'backfill vault_tags.project_id from linked keys' do
      keys_tbl = quote_table_name('keys')
      rows = select_all(
        "SELECT kvt.tag_id AS tag_id, MIN(k.project_id) AS pid " \
        "FROM keys_vault_tags kvt " \
        "JOIN #{keys_tbl} k ON k.id = kvt.key_id " \
        "GROUP BY kvt.tag_id"
      )
      rows.each do |r|
        pid = r['pid']
        next if pid.nil?
        execute(
          "UPDATE #{quote_table_name('vault_tags')} SET project_id = #{pid.to_i} " \
          "WHERE id = #{r['tag_id'].to_i} AND project_id IS NULL"
        )
      end
    end

    unless index_exists?(:vault_tags, [:project_id, :name], name: INDEX_NAME)
      add_index :vault_tags, [:project_id, :name], unique: true, name: INDEX_NAME
    end
  end

  def down
    remove_index :vault_tags, name: INDEX_NAME if index_exists?(:vault_tags, [:project_id, :name], name: INDEX_NAME)
    remove_column :vault_tags, :project_id if column_exists?(:vault_tags, :project_id)
  end
end
