require File.expand_path('../../test_helper', __FILE__)

class KeyFileTest < Vault::UnitTest
  fixtures :projects

  def setup
    # Real cipher so encryption actually happens (VaultCipher, AES-128 key).
    Setting.plugin_vault = { 'encryption_key' => '0123456789abcdef' }
    @project = Project.find(1)
  end

  def new_keyfile(content)
    kf = Vault::KeyFile.new(project: @project, name: 'id_rsa', file: 'id_rsa')
    kf.file_data = content
    kf
  end

  def test_file_stored_encrypted_and_round_trips
    secret = "SECRET-KEY-BYTES\nline2\n"
    kf = new_keyfile(secret)
    kf.save!

    raw = Vault::KeyFile.connection.select_value("SELECT file_data FROM keys WHERE id = #{kf.id}")
    refute_equal secret, raw, 'file content must not be stored in plaintext'
    assert_equal secret, Vault::KeyFile.find(kf.id).decrypt_file
  end

  def test_name_only_update_does_not_double_encrypt
    secret = "PLAINTEXT-CONTENT\n"
    kf = new_keyfile(secret)
    kf.save!

    reloaded = Vault::KeyFile.find(kf.id)
    reloaded.update!(name: 'renamed') # no new file assigned
    assert_equal secret, Vault::KeyFile.find(kf.id).decrypt_file
  end

  def test_no_file_data_is_nil_safe
    kf = Vault::KeyFile.new(project: @project, name: 'empty')
    assert kf.save
    assert_nil kf.decrypt_file
  end

  def test_upload_setter_reads_name_and_bytes
    upload = Struct.new(:original_filename, :io) do
      def read; io; end
    end.new('server.key', "BYTES\n")
    kf = Vault::KeyFile.new(project: @project)
    kf.upload = upload
    assert_equal 'server.key', kf.file
    kf.save!
    assert_equal "BYTES\n", Vault::KeyFile.find(kf.id).decrypt_file
  end
end
