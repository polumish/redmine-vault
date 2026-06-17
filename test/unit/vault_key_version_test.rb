require File.expand_path('../../test_helper', __FILE__)

class VaultKeyVersionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def setup
    @project = Project.find(1)
    User.current = User.find(1) # admin
  end

  def test_model_and_association_load
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    assert_equal 0, k.vault_key_versions.count
    v = k.vault_key_versions.create!(name: 'n', body: BodyCipher.encrypt('old'),
                                     changed_fields: 'body', changed_at: Time.current)
    assert_equal 'old', v.decrypted_body
    assert_equal ['body'], v.changed_field_list
  end

  def test_versions_destroyed_with_key
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    v = k.vault_key_versions.create!(changed_fields: 'body', changed_at: Time.current)
    k.destroy
    assert_nil Vault::KeyVersion.find_by(id: v.id)
  end

  def test_no_version_on_create
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    assert_equal 0, k.vault_key_versions.count
  end

  def test_version_on_body_change_stores_old_ciphertext
    k = Vault::Password.create!(project: @project, name: 'n', body: 'old-secret')
    k.update!(body: 'new-secret')
    assert_equal 1, k.vault_key_versions.count
    v = k.vault_key_versions.first
    assert_includes v.changed_field_list, 'body'
    assert BodyCipher.marked?(v.body), 'stored old body must be GCM ciphertext'
    refute_equal 'old-secret', v.body
    assert_equal 'old-secret', v.decrypted_body
  end

  def test_version_on_metadata_change_only_lists_changed
    k = Vault::Password.create!(project: @project, name: 'n', login: 'old', url: 'http://old')
    k.update!(login: 'new')
    v = k.vault_key_versions.first
    assert_equal ['login'], v.changed_field_list
    assert_equal 'old', v.login
  end

  def test_no_version_on_noop_save
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    k.save!
    assert_equal 0, k.vault_key_versions.count
  end

  def test_no_version_on_tags_only_change
    k = Vault::Password.create!(project: @project, name: 'n', body: 'secret')
    k.tags = Vault::Tag.create_from_string('alpha', @project)
    assert_equal 0, k.vault_key_versions.count
  end

  def test_records_changed_by_and_at
    k = Vault::Password.create!(project: @project, name: 'n', body: 'old')
    User.current = User.find(2)
    k.update!(body: 'new')
    v = k.vault_key_versions.first
    assert_equal User.find(2).id, v.changed_by_id
    assert_not_nil v.changed_at
  end

  def test_keeps_all_versions
    k = Vault::Password.create!(project: @project, name: 'n', body: 'v1')
    k.update!(body: 'v2')
    k.update!(body: 'v3')
    assert_equal 2, k.vault_key_versions.count
    assert_equal ['v1', 'v2'], k.vault_key_versions.order(:id).map(&:decrypted_body)
  end
end
