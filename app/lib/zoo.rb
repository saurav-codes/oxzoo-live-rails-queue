# The zoo identity of this process (DESIGN.md, contract).
module Zoo
  NAME = "rails-queue".freeze
  STACK = "Rails 8 + Puma + Solid Queue".freeze
  STARTED_AT = Time.now.utc
  TRACE_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  # Callers allowed to sign with WEBHOOK_SECRET.
  WEBHOOK_CALLERS = %w[mesh-shop laravel-jobs].freeze
  PEER = "laravel-jobs".freeze

  module_function

  def env(name)
    value = ENV[name]
    value.presence
  end

  def server
    env("PUBLIC_HOST").to_s.split(".").find { |label| label.match?(/\As[0-9]+\z/) } || "local"
  end

  def release
    env("OX_RELEASE")&.slice(0, 12) || "unknown"
  end

  def ox_env
    env("OX_ENV") || "local"
  end

  def hop_name
    "#{NAME}@#{server}"
  end

  def identity
    { name: NAME, stack: STACK, server: server, release: release, env: ox_env }
  end

  def health
    identity.merge(
      uptime_s: (Time.now.utc - STARTED_AT).to_i,
      started_at: STARTED_AT.iso8601,
      build: { tag: "zoo-1", runtime: "ruby #{RUBY_VERSION}" }
    )
  end

  def panel_origins
    env("ZOO_PANEL_ORIGIN").to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def valid_trace?(id)
    id.is_a?(String) && TRACE_RE.match?(id)
  end

  def vars
    [
      secret_var("WEBHOOK_SECRET", "verifies"),
      url_var("LARAVEL_URL", PEER),
      plain_var("ZOO_PANEL_ORIGIN")
    ]
  end

  def secret_var(name, role)
    value = env(name)
    value ? { name: name, fp: ZooSig.fp(value), role: role } : { name: name, missing: true, role: role }
  end

  def url_var(name, peer)
    value = env(name)
    value ? { name: name, value: value, role: "url", peer: peer } : { name: name, missing: true, role: "url" }
  end

  def plain_var(name)
    value = env(name)
    value ? { name: name, value: value, role: "plain" } : { name: name, missing: true, role: "plain" }
  end
end
