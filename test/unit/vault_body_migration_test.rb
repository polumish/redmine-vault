require File.expand_path('../../test_helper', __FILE__)
require File.expand_path('../../../db/migrate/013_reencrypt_bodies_gcm', __FILE__)

class VaultBodyMigrationTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
    Setting.plugin_vault = { 'use_null_encryption' => true }
  end

  def teardown
    Setting.plugin_vault = {}
  end

  def raw_body(id)
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.select_value("SELECT body FROM #{t} WHERE id=#{id.to_i}")
  end

  def test_migrates_legacy_unmarked_row
    k = Vault::Password.create!(project: @project, name: 'm1', body: 'x')
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.execute("UPDATE #{t} SET body='plain-secret' WHERE id=#{k.id}")
    ReencryptBodiesGcm.new.up
    assert BodyCipher.marked?(raw_body(k.id))
    assert_equal 'plain-secret', BodyCipher.decrypt(raw_body(k.id))
  end

  def test_idempotent_skips_already_marked
    k = Vault::Password.create!(project: @project, name: 'm2', body: 'abc')
    before = raw_body(k.id)
    ReencryptBodiesGcm.new.up
    assert_equal before, raw_body(k.id), 'already-marked row must be untouched'
  end
end
