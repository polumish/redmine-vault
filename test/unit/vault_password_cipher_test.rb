require File.expand_path('../../test_helper', __FILE__)

class VaultPasswordCipherTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules

  def setup
    @project = Project.find(1)
    unless @project.enabled_module_names.include?('keys')
      EnabledModule.create!(project: @project, name: 'keys')
    end
  end

  def raw_body(id)
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.select_value("SELECT body FROM #{t} WHERE id=#{id.to_i}")
  end

  def test_body_stored_encrypted_and_marked
    k = Vault::Password.create!(project: @project, name: 'p1', body: 'hunter2')
    assert BodyCipher.marked?(raw_body(k.id)), 'stored body must be GCM-marked'
    refute_equal 'hunter2', raw_body(k.id)
  end

  def test_decrypt_returns_plaintext
    k = Vault::Password.create!(project: @project, name: 'p2', body: 's3cr3t')
    r = Vault::Password.find(k.id)
    r.decrypt!
    assert_equal 's3cr3t', r.body
  end

  def test_encrypt_skips_already_marked
    marked = BodyCipher.encrypt('zzz')
    k = Vault::Password.new(project: @project, name: 'p5')
    k.body = marked
    k.encrypt!
    assert_equal marked, k.body, 'already-marked value must not be re-encrypted'
    assert_equal 'zzz', BodyCipher.decrypt(k.body)
  end

  def test_decrypt_falls_back_to_legacy_for_unmarked
    Setting.plugin_vault = { 'use_null_encryption' => true }
    k = Vault::Password.create!(project: @project, name: 'p3', body: 'x')
    t = Vault::Key.connection.quote_table_name('keys')
    Vault::Key.connection.execute("UPDATE #{t} SET body='legacy-plain' WHERE id=#{k.id}")
    r = Vault::Password.find(k.id)
    r.decrypt!
    assert_equal 'legacy-plain', r.body
  ensure
    Setting.plugin_vault = {}
  end

  def test_blank_body_stays_blank
    k = Vault::Password.create!(project: @project, name: 'p6', body: '')
    assert_equal '', raw_body(k.id).to_s
  end
end
