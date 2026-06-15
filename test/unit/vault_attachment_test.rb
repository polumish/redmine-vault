require File.expand_path('../../test_helper', __FILE__)

class VaultAttachmentTest < Vault::UnitTest
  fixtures :projects

  def setup
    @project = Project.find(1)
    @key = Vault::Password.create!(project: @project, name: 'pw', body: 'secret')
  end

  def test_file_stored_encrypted_and_round_trips
    conf = "[Interface]\nPrivateKey=abc\n"
    att = @key.vault_attachments.create!(filename: 'wg.conf', file_data: conf, comment: 'vpn')
    raw = Vault::Attachment.connection.select_value(
      "SELECT file_data FROM vault_attachments WHERE id = #{att.id}")
    refute_equal conf, raw, 'file content must not be stored in plaintext'
    assert_equal conf, Vault::Attachment.find(att.id).decrypt_data
    assert_equal 'vpn', att.comment
  end

  def test_multiple_attachments_per_key
    @key.vault_attachments.create!(filename: 'a', file_data: 'aaa')
    @key.vault_attachments.create!(filename: 'b', file_data: 'bbb')
    assert_equal 2, @key.reload.vault_attachments.count
  end

  def test_comment_only_update_does_not_corrupt_file
    conf = "DATA\nbytes\n"
    att = @key.vault_attachments.create!(filename: 'x', file_data: conf)
    att.update!(comment: 'note')
    assert_equal conf, Vault::Attachment.find(att.id).decrypt_data
  end

  def test_upload_assigns_name_and_bytes
    require 'stringio'
    f = ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new('hello'), filename: 'h.txt')
    att = @key.vault_attachments.build
    att.upload = f
    att.save!
    assert_equal 'h.txt', att.filename
    assert_equal 'hello', Vault::Attachment.find(att.id).decrypt_data
  end

  # Files attach to any key type, not only Vault::KeyFile.
  def test_attachment_works_on_password_type
    assert_instance_of Vault::Password, @key
    att = @key.vault_attachments.create!(filename: 'note.txt', file_data: 'plain')
    assert_equal 'plain', Vault::Attachment.find(att.id).decrypt_data
  end

  def test_destroying_key_destroys_attachments
    att = @key.vault_attachments.create!(filename: 'x', file_data: 'y')
    @key.destroy
    assert_nil Vault::Attachment.find_by(id: att.id)
  end
end
