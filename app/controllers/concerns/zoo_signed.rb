# Verifies zoo-sig v1 on the raw body, read with a 64 KB cap before hashing.
module ZooSigned
  extend ActiveSupport::Concern

  private

  # Returns [caller, body], or renders the error and returns nil.
  def verify_signed(allowed)
    if request.content_length.to_i > ZooSig::MAX_BODY
      render json: { ok: false, error: "body over 64 KB" }, status: :content_too_large
      return
    end
    body = request.body&.read(ZooSig::MAX_BODY + 1).to_s
    if body.bytesize > ZooSig::MAX_BODY
      render json: { ok: false, error: "body over 64 KB" }, status: :content_too_large
      return
    end
    key = Zoo.env("WEBHOOK_SECRET")
    unless key
      render json: { ok: false, error: "WEBHOOK_SECRET is not set" }, status: :internal_server_error
      return
    end
    caller_name = ZooSig.verify!(key, request.headers[ZooSig::HEADER], request.method, request.fullpath, body, allowed: allowed)
    [caller_name, body]
  rescue ZooSig::Invalid => e
    render json: { ok: false, error: e.message }, status: :unauthorized
    nil
  end

  def signed_trace
    trace = request.headers["X-Zoo-Trace"]
    trace if Zoo.valid_trace?(trace)
  end
end
