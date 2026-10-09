require_relative "boot"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module RailsQueue
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[tasks])
    config.time_zone = "UTC"
    config.active_job.queue_adapter = :solid_queue
    # Finished jobs are deleted at once, so probe jobs leave nothing behind.
    config.solid_queue.preserve_finished_jobs = false
    config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  end
end
