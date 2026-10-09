# The zoo contract endpoints (DESIGN.md).
class ZooController < ActionController::API
  include ZooSigned

  after_action :cors, except: :verify

  def health
    render json: Zoo.health
  end

  def probe
    render json: ZooProbe.run
  rescue ZooProbe::Busy
    render json: { error: "probe busy" }, status: :too_many_requests
  end

  def verify
    caller_name, = verify_signed(Zoo::WEBHOOK_CALLERS)
    return unless caller_name
    trace = signed_trace
    Hop.record(trace, "verified", "signed verify from #{caller_name}") if trace
    render json: {
      ok: true, name: Zoo::NAME, public_url: Zoo.env("PUBLIC_URL"), verified_by: "WEBHOOK_SECRET",
      key_fp: ZooSig.fp(Zoo.env("WEBHOOK_SECRET")), caller: caller_name, server: Zoo.server, release: Zoo.release
    }
  end

  def trace
    id = params[:id].to_s
    unless Zoo.valid_trace?(id)
      render json: { error: "trace id must be a lowercase uuid" }, status: :bad_request
      return
    end
    hops = Hop.where(trace: id).order(:created_at, :id).map(&:as_hop)
    render json: { trace: id, found: hops.any?, hops: hops }
  end

  def preflight
    if Zoo.panel_origins.include?(request.origin)
      response.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
      response.set_header("Access-Control-Allow-Headers", "Content-Type")
      response.set_header("Access-Control-Max-Age", "600")
    end
    head :no_content
  end

  private

  # Only listed origins get CORS headers; never *, never credentials.
  def cors
    origin = request.origin
    return unless origin && Zoo.panel_origins.include?(origin)
    response.set_header("Access-Control-Allow-Origin", origin)
    response.set_header("Vary", "Origin")
  end
end
