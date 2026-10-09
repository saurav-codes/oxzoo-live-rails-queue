Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_job.queue_adapter = :test
  config.secret_key_base = "test-only-secret"
  config.active_support.deprecation = :stderr
  config.log_level = :warn
end
