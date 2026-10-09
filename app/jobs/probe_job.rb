# The probe's Solid Queue round trip: the worker writes the token row the
# probe waits for. A job older than the probe's wait is dropped, so a late
# worker leaves nothing behind.
class ProbeJob < ApplicationJob
  queue_as :default

  def perform(token)
    queued = enqueued_at.is_a?(String) ? Time.iso8601(enqueued_at) : enqueued_at
    return if queued && Time.now.utc - queued > 5
    ProbeRow.create!(token: token)
  end
end
