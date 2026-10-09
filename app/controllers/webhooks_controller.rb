# POST /webhooks/zoo from mesh-shop (shop-order) and laravel-jobs (ping-pong).
class WebhooksController < ActionController::API
  include ZooSigned

  EVENT_RE = /\A[a-z0-9._-]{1,64}\z/

  def create
    caller_name, body = verify_signed(Zoo::WEBHOOK_CALLERS)
    return unless caller_name
    payload = JSON.parse(body)
    trace, source, event = payload.values_at("trace", "source", "event") if payload.is_a?(Hash)
    return bad("trace must be a lowercase uuid") unless Zoo.valid_trace?(trace)
    return bad("source must equal the signing caller") unless source == caller_name
    return bad("event must match #{EVENT_RE.source}") unless event.is_a?(String) && EVENT_RE.match?(event)

    Hop.record(trace, "webhook-received", "#{event} from #{caller_name}")
    ZooWebhookJob.perform_later(trace, source, event)
    render json: { ok: true, trace: trace, queued: true }, status: :accepted
  rescue JSON::ParserError
    bad("body must be JSON")
  end

  private

  def bad(error)
    render json: { ok: false, error: error }, status: :unprocessable_content
  end
end
