require File.expand_path('../../test_helper', __FILE__)

class VaultBodyCipherTest < ActiveSupport::TestCase
  def test_round_trip
    %w[hunter2 пароль123 a].each do |p|
      enc = BodyCipher.encrypt(p)
      assert BodyCipher.marked?(enc), "encrypt output must be marked"
      refute_equal p, enc
      assert_equal p, BodyCipher.decrypt(enc)
    end
  end

  def test_round_trip_long_and_utf8
    p = ('Ключ-' * 500) + "\u{1F510}"
    assert_equal p, BodyCipher.decrypt(BodyCipher.encrypt(p))
  end

  def test_marked_is_false_for_plaintext_legacy_base64_and_nil
    refute BodyCipher.marked?('hunter2')
    refute BodyCipher.marked?(Base64.strict_encode64('whatever'))
    refute BodyCipher.marked?(nil)
  end

  def test_nil_passthrough
    assert_nil BodyCipher.encrypt(nil)
  end

  def test_tamper_detection_raises
    enc = BodyCipher.encrypt('secret-value')
    raw = Base64.strict_decode64(enc[BodyCipher::MARKER.length..])
    raw[-1] = (raw[-1].ord ^ 0xFF).chr
    tampered = BodyCipher::MARKER + Base64.strict_encode64(raw)
    assert_raises(OpenSSL::Cipher::CipherError) { BodyCipher.decrypt(tampered) }
  end

  def test_read_decrypts_gcm
    enc = BodyCipher.encrypt('hunter2')
    assert_equal 'hunter2', BodyCipher.read(enc)
  end

  def test_read_falls_back_to_legacy_for_unmarked
    legacy = Encryptor.encrypt('legacy-secret')
    refute BodyCipher.marked?(legacy), 'legacy value must not be GCM-marked'
    assert_equal 'legacy-secret', BodyCipher.read(legacy)
  end

  def test_read_passes_through_nil_and_empty
    assert_nil BodyCipher.read(nil)
    assert_equal '', BodyCipher.read('')
  end
end
