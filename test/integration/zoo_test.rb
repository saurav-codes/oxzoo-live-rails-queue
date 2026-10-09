require "test_helper"

class ZooTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  KEY = "zoo-test-key-0123456789abcdef".freeze
  TRACE = "0b7c1e2a-3f4d-4a5b-8c6d-7e8f9a0b1c2d".freeze
  PANEL = "https://zoo-control.s1.zoo.sorv.dev".freeze

  setup { @saved = ENV.to_h.slice("WEBHOOK_SECRET", "ZOO_PANEL_ORIGIN", "PUBLIC_URL") }
  teardown { %w[WEBHOOK_SECRET ZOO_PANEL_ORIGIN PUBLIC_URL].each { |k| ENV[k] = @saved[k] } }

  def signed(method, path, body = "", caller_name: "laravel-jobs", key: KEY, trace: nil)
    headers = { "X-Zoo-Signature" => ZooSig.header(key, caller_name, method, path, body), "CONTENT_TYPE" => "application/json" }
    headers["X-Zoo-Trace"] = trace if trace
    send(method.downcase, path, params: body, headers: headers)
  end

  test "health is cheap and shaped" do
    get "/_zoo/health"
    assert_response :ok
    json = response.parsed_body
    assert_equal "rails-queue", json["name"]
    assert_equal "unknown", json["release"]
    assert_match(/\Aruby /, json.dig("build", "runtime"))
  end

  test "CORS only for listed origins" do
    ENV["ZOO_PANEL_ORIGIN"] = "#{PANEL},http://localhost:5173"
    get "/_zoo/health", headers: { "Origin" => PANEL }
    assert_equal PANEL, response.headers["Access-Control-Allow-Origin"]
    assert_equal "Origin", response.headers["Vary"]
    assert_nil response.headers["Access-Control-Allow-Credentials"]

    get "/_zoo/health", headers: { "Origin" => "https://evil.example" }
    assert_nil response.headers["Access-Control-Allow-Origin"]

    process :options, "/_zoo/probe", headers: { "Origin" => PANEL }
    assert_response :no_content
    assert_equal "GET, POST, OPTIONS", response.headers["Access-Control-Allow-Methods"]
    assert_equal "Content-Type", response.headers["Access-Control-Allow-Headers"]
    assert_equal "600", response.headers["Access-Control-Max-Age"]
  end

  test "verify checks the signature" do
    ENV["WEBHOOK_SECRET"] = KEY
    ENV["PUBLIC_URL"] = "https://rails-queue.s1.zoo.sorv.dev"
    signed("GET", "/_zoo/verify")
    assert_response :ok
    json = response.parsed_body
    assert_equal ["rails-queue", "915a", "laravel-jobs", "WEBHOOK_SECRET", "https://rails-queue.s1.zoo.sorv.dev"],
      json.values_at("name", "key_fp", "caller", "verified_by", "public_url")

    get "/_zoo/verify"
    assert_response :unauthorized
    assert_equal({ "ok" => false, "error" => "missing signature" }, response.parsed_body)

    signed("GET", "/_zoo/verify", caller_name: "celery-hub")
    assert_equal "unknown caller", response.parsed_body["error"]

    signed("GET", "/_zoo/verify", key: "wrong")
    assert_equal "bad signature", response.parsed_body["error"]
  end

  test "webhook records the hop and enqueues the job" do
    ENV["WEBHOOK_SECRET"] = KEY
    body = JSON.generate(trace: TRACE, source: "laravel-jobs", event: "ping")
    assert_enqueued_with(job: ZooWebhookJob, args: [TRACE, "laravel-jobs", "ping"]) do
      signed("POST", "/webhooks/zoo", body)
    end
    assert_response :accepted
    get "/_zoo/trace/#{TRACE}"
    assert_equal true, response.parsed_body["found"]
    assert_equal ["webhook-received"], response.parsed_body["hops"].map { |h| h["step"] }
  end

  test "webhook refuses bad input" do
    ENV["WEBHOOK_SECRET"] = KEY
    signed("POST", "/webhooks/zoo", JSON.generate(trace: "nope", source: "laravel-jobs", event: "ping"))
    assert_response :unprocessable_content
    signed("POST", "/webhooks/zoo", JSON.generate(trace: TRACE, source: "mesh-shop", event: "ping"))
    assert_response :unprocessable_content
    signed("POST", "/webhooks/zoo", "x" * (64 * 1024 + 1))
    assert_response :content_too_large
    post "/webhooks/zoo", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
    assert_no_enqueued_jobs
  end

  test "trace ids are validated" do
    get "/_zoo/trace/not-a-uuid"
    assert_response :bad_request
    get "/_zoo/trace/#{TRACE}"
    assert_equal({ "trace" => TRACE, "found" => false, "hops" => [] }, response.parsed_body)
  end

  test "probe reports honest failures and fingerprints only" do
    ENV["WEBHOOK_SECRET"] = KEY
    get "/_zoo/probe"
    assert_response :ok
    json = response.parsed_body
    checks = json["checks"].index_by { |c| c["id"] }
    assert checks["postgres"]["ok"], checks["postgres"].inspect
    refute checks["worker-heartbeat"]["ok"]
    refute json["ok"]
    assert_includes checks["peer:laravel-jobs"]["error"], "LARAVEL_URL is not set"
    secret = json["vars"].find { |v| v["name"] == "WEBHOOK_SECRET" }
    assert_equal({ "name" => "WEBHOOK_SECRET", "fp" => "915a", "role" => "verifies" }, secret)
    refute_includes response.body, KEY
  end

  test "status page and JSON" do
    get "/"
    assert_response :ok
    assert_includes response.body, "Solid Queue"
    get "/api/queue"
    assert_equal 0, response.parsed_body["failed"]
  end
end
