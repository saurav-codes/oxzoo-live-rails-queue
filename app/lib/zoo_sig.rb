require "openssl"
require "digest"

# zoo-sig v1 (DESIGN.md): X-Zoo-Signature: t=<unix>,caller=<name>,sig=<hex>
# sig = hex(HMAC-SHA256(key, "<t>.<METHOD>.<path with query>.<hex sha256 body>"))
module ZooSig
  HEADER = "X-Zoo-Signature".freeze
  MAX_SKEW = 300
  MAX_BODY = 64 * 1024
  HEADER_RE = /\At=(\d{1,12}),caller=([a-z][a-z0-9-]{0,40}),sig=([0-9a-f]{64})\z/

  class Invalid < StandardError; end

  module_function

  def sign(key, time, method, path, body)
    payload = "#{time}.#{method.to_s.upcase}.#{path}.#{Digest::SHA256.hexdigest(body.to_s)}"
    OpenSSL::HMAC.hexdigest("SHA256", key, payload)
  end

  def header(key, caller_name, method, path, body, time: Time.now.to_i)
    "t=#{time},caller=#{caller_name},sig=#{sign(key, time, method, path, body)}"
  end

  # Returns the verified caller, or raises Invalid with one of the
  # contract's reasons.
  def verify!(key, value, method, path, body, allowed:, now: Time.now.to_i)
    raise Invalid, "missing signature" if value.blank?
    match = HEADER_RE.match(value)
    raise Invalid, "bad format" unless match
    time, caller_name, sig = match[1].to_i, match[2], match[3]
    raise Invalid, "expired" if (now - time).abs > MAX_SKEW
    raise Invalid, "unknown caller" unless allowed.include?(caller_name)
    expected = sign(key, time, method, path, body)
    raise Invalid, "bad signature" unless OpenSSL.fixed_length_secure_compare(expected, sig)
    caller_name
  end

  # Last 4 hex characters of sha256(value): the only form a secret is shown in.
  def fp(value)
    Digest::SHA256.hexdigest(value.to_s)[-4..]
  end
end
