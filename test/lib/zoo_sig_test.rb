require "test_helper"

# DESIGN.md test vectors.
class ZooSigTest < ActiveSupport::TestCase
  KEY = "zoo-test-key-0123456789abcdef".freeze
  T = 1_760_000_000
  BODY = '{"sku":"ZOO-1"}'.freeze

  test "body hash vector" do
    assert_equal "cc2860a77ea231854ea58f9cb05f3217059f80a8e95d7b69a204293ae4f3a444", Digest::SHA256.hexdigest(BODY)
  end

  test "POST vector" do
    assert_equal "50c22839fe6a06cb51a9fd25167d9e457eb0b5ee63ce696f4c5428a6b9271da1",
      ZooSig.sign(KEY, T, "POST", "/api/items?x=1", BODY)
  end

  test "GET vector with empty body" do
    assert_equal "9a404bebaa32497c5ed39ef8990e8466428f8023d6aa9f5acc94f16fb7670ecb",
      ZooSig.sign(KEY, T, "get", "/_zoo/verify", "")
  end

  test "fingerprint vector" do
    assert_equal "915a", ZooSig.fp(KEY)
  end

  test "verify accepts a good header and names the caller" do
    header = ZooSig.header(KEY, "mesh-shop", "POST", "/api/items?x=1", BODY, time: T)
    assert_equal "mesh-shop", ZooSig.verify!(KEY, header, "POST", "/api/items?x=1", BODY, allowed: ["mesh-shop"], now: T + 299)
  end

  test "verify reasons" do
    good = ZooSig.header(KEY, "mesh-shop", "GET", "/_zoo/verify", "", time: T)
    cases = {
      nil => "missing signature",
      "t=1,sig=zz" => "bad format",
      good => "expired",
      ZooSig.header(KEY, "evil", "GET", "/_zoo/verify", "", time: T) => "unknown caller",
      ZooSig.header("other-key", "mesh-shop", "GET", "/_zoo/verify", "", time: T) => "bad signature"
    }
    cases.each do |header, reason|
      now = reason == "expired" ? T + 301 : T
      error = assert_raises(ZooSig::Invalid) do
        ZooSig.verify!(KEY, header, "GET", "/_zoo/verify", "", allowed: ["mesh-shop"], now: now)
      end
      assert_equal reason, error.message
    end
  end

  test "a changed body or path fails" do
    header = ZooSig.header(KEY, "mesh-shop", "POST", "/api/items?x=1", BODY, time: T)
    assert_raises(ZooSig::Invalid) { ZooSig.verify!(KEY, header, "POST", "/api/items?x=2", BODY, allowed: ["mesh-shop"], now: T) }
    assert_raises(ZooSig::Invalid) { ZooSig.verify!(KEY, header, "POST", "/api/items?x=1", "{}", allowed: ["mesh-shop"], now: T) }
  end

  test "trace id validation" do
    assert Zoo.valid_trace?("0b7c1e2a-3f4d-4a5b-8c6d-7e8f9a0b1c2d")
    refute Zoo.valid_trace?("0B7C1E2A-3F4D-4A5B-8C6D-7E8F9A0B1C2D")
    refute Zoo.valid_trace?("0b7c1e2a-3f4d-4a5b-8c6d-7e8f9a0b1c2d\n")
    refute Zoo.valid_trace?("../etc/passwd")
    refute Zoo.valid_trace?(nil)
  end

  test "server label comes from PUBLIC_HOST" do
    with_env("PUBLIC_HOST" => "rails-queue.s1.zoo.sorv.dev") { assert_equal "s1", Zoo.server }
    with_env("PUBLIC_HOST" => "localhost") { assert_equal "local", Zoo.server }
  end
end
