require File.expand_path('../../test_helper', __FILE__)

class TagTest < Vault::UnitTest
  fixtures :projects
  plugin_fixtures :keys, :vault_tags, :keys_vault_tags

  def setup
    @project = Project.find(1)
  end

  def test_cloud
    cloud = Vault::Tag.cloud_for_project(1)
    assert_equal ['ssh', 'ftp'], cloud
  end

  def test_cloud_is_project_scoped
    # 'cisco' belongs to project 2 only
    refute_includes Vault::Tag.cloud_for_project(1), 'cisco'
    assert_includes Vault::Tag.cloud_for_project(2), 'cisco'
  end

  def test_create_from_string_basic
    tags = Vault::Tag.create_from_string('mysql, nginx', @project)
    assert_equal ['mysql', 'nginx'], tags.map(&:name)
    assert tags.all?(&:persisted?)
    assert tags.all? { |t| t.project_id == @project.id }
  end

  def test_create_from_string_blank_returns_empty
    assert_equal [], Vault::Tag.create_from_string('', @project)
    assert_equal [], Vault::Tag.create_from_string(nil, @project)
  end

  # Regression: blank tokens used to yield nil entries -> AssociationTypeMismatch
  # -> HTTP 500 when assigned to key.tags.
  def test_create_from_string_skips_blanks_no_nil
    tags = Vault::Tag.create_from_string('a,,b', @project)
    refute_includes tags, nil
    assert_equal ['a', 'b'], tags.map(&:name)
  end

  def test_create_from_string_dedupes_and_downcases
    tags = Vault::Tag.create_from_string('SSH, ssh,  Ssh ', @project)
    assert_equal ['ssh'], tags.map(&:name)
  end

  def test_create_from_string_is_idempotent
    a = Vault::Tag.create_from_string('repeatme', @project)
    b = Vault::Tag.create_from_string('repeatme', @project)
    assert_equal a.map(&:id), b.map(&:id)
    assert_equal 1, Vault::Tag.where(project_id: @project.id, name: 'repeatme').count
  end

  def test_create_from_string_reuses_existing_tag
    existing = Vault::Tag.find(1) # 'ssh' in project 1
    tags = Vault::Tag.create_from_string('ssh', @project)
    assert_equal [existing.id], tags.map(&:id)
  end

  def test_same_name_isolated_per_project
    p1 = Vault::Tag.create_from_string('shared', Project.find(1)).first
    p2 = Vault::Tag.create_from_string('shared', Project.find(2)).first
    refute_equal p1.id, p2.id
    assert_equal 1, p1.project_id
    assert_equal 2, p2.project_id
  end

  def test_assigning_to_key_does_not_raise
    key = Vault::Key.find(1)
    assert_nothing_raised do
      key.tags = Vault::Tag.create_from_string('a,,b, a', @project)
      key.save!
    end
    assert_equal ['a', 'b'], key.reload.tags.map(&:name)
  end
end
