require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  # Caddy terminates TLS in front of puma.
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
  config.log_level = :info
  config.log_tags = [:request_id]
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]
  config.hosts = [ENV["PUBLIC_HOST"]].compact
  # ox's health check calls puma on 127.0.0.1 directly.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
