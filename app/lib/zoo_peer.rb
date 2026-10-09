require "net/http"
require "json"
require "timeout"

# Signed HTTP calls to peers. Every call has connect and read timeouts.
module ZooPeer
  Response = Struct.new(:status, :json)

  module_function

  def call(method, base_url, path, key:, body: "", trace: nil, timeout: 8)
    uri = URI.parse(base_url.to_s.chomp("/") + path)
    raise ArgumentError, "peer URL must be http or https" unless %w[http https].include?(uri.scheme)
    request = (method == "POST" ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri)
    request["X-Zoo-Signature"] = ZooSig.header(key, Zoo::NAME, method, uri.request_uri, body)
    request["X-Zoo-Trace"] = trace if trace
    request["Accept"] = "application/json"
    if method == "POST"
      request["Content-Type"] = "application/json"
      request.body = body
    end
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = timeout
    http.read_timeout = timeout
    http.write_timeout = timeout
    # The per-step timeouts above can add up; this caps the whole call.
    response = Timeout.timeout(timeout, Timeout::Error, "timeout after #{(timeout * 1000).to_i} ms") do
      http.start { |conn| conn.request(request) }
    end
    raw = response.body.to_s.byteslice(0, ZooSig::MAX_BODY)
    json = begin
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
    Response.new(response.code.to_i, json)
  end
end
