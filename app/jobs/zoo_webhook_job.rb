# Runs in the bin/jobs worker for each verified webhook. For laravel-jobs
# (the ping-pong chain) it sends a signed ack back to LARAVEL_URL, a
# variable of this project, never a URL from the payload.
class ZooWebhookJob < ApplicationJob
  class AckFailed < StandardError; end

  queue_as :default
  retry_on AckFailed, Timeout::Error, SystemCallError, wait: 5.seconds, attempts: 3

  def perform(trace, source, event)
    Hop.record(trace, "job-done", "#{event} from #{source} on #{Zoo.hop_name}")
    return unless source == "laravel-jobs"

    url, key = Zoo.env("LARAVEL_URL"), Zoo.env("WEBHOOK_SECRET")
    raise AckFailed, "LARAVEL_URL is not set" unless url
    raise AckFailed, "WEBHOOK_SECRET is not set" unless key
    body = JSON.generate(trace: trace)
    response = ZooPeer.call("POST", url, "/api/acks", key: key, body: body, trace: trace)
    raise AckFailed, "ack answered HTTP #{response.status}" unless (200..299).cover?(response.status)
    Hop.record(trace, "ack-sent", "laravel-jobs answered HTTP #{response.status}")
  end
end
