require "test_helper"
require "socket"

class ZooWebhookJobTest < ActiveJob::TestCase
  KEY = "zoo-test-key-0123456789abcdef".freeze
  TRACE = "0b7c1e2a-3f4d-4a5b-8c6d-7e8f9a0b1c2d".freeze

  # A one-shot HTTP server standing in for laravel-jobs /api/acks.
  def fake_laravel(status)
    server = TCPServer.new("127.0.0.1", 0)
    seen = {}
    thread = Thread.new do
      client = server.accept
      seen[:request_line] = client.gets
      while (line = client.gets) && line != "\r\n"
        name, value = line.split(": ", 2)
        seen[name.downcase] = value.strip
      end
      seen[:body] = client.read(seen["content-length"].to_i)
      client.write("HTTP/1.1 #{status} OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\nConnection: close\r\n\r\n{\"ok\":true}")
      client.close
    end
    [server.addr[1], seen, thread]
  end

  test "laravel-jobs webhooks get a signed ack" do
    port, seen, thread = fake_laravel(200)
    with_env("LARAVEL_URL" => "http://127.0.0.1:#{port}", "WEBHOOK_SECRET" => KEY) do
      ZooWebhookJob.perform_now(TRACE, "laravel-jobs", "ping")
    end
    thread.join(5)
    assert_equal "POST /api/acks HTTP/1.1\r\n", seen[:request_line]
    assert_equal({ "trace" => TRACE }, JSON.parse(seen[:body]))
    assert_equal TRACE, seen["x-zoo-trace"]
    assert_equal "rails-queue", ZooSig.verify!(KEY, seen["x-zoo-signature"], "POST", "/api/acks", seen[:body], allowed: ["rails-queue"])
    assert_equal %w[job-done ack-sent], Hop.where(trace: TRACE).order(:id).pluck(:step)
  end

  test "mesh-shop webhooks only record job-done" do
    ZooWebhookJob.perform_now(TRACE, "mesh-shop", "order.fulfilled")
    assert_equal %w[job-done], Hop.where(trace: TRACE).pluck(:step)
  end

  test "a failed ack is retried, not recorded" do
    port, _seen, thread = fake_laravel(500)
    with_env("LARAVEL_URL" => "http://127.0.0.1:#{port}", "WEBHOOK_SECRET" => KEY) do
      assert_enqueued_with(job: ZooWebhookJob) { ZooWebhookJob.perform_now(TRACE, "laravel-jobs", "ping") }
    end
    thread.join(5)
    assert_equal %w[job-done], Hop.where(trace: TRACE).pluck(:step)
  end
end
