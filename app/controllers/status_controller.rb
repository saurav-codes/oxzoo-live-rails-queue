# The status page and its JSON: what the queue and the chains are doing.
class StatusController < ApplicationController
  def index
    @identity = Zoo.health
    @queue = queue_stats
    @hops = recent_hops
  end

  def hops
    render json: { hops: recent_hops.map { |h| h.as_hop.merge(trace: h.trace) } }
  end

  def queue
    render json: queue_stats
  end

  private

  def recent_hops
    Hop.order(created_at: :desc, id: :desc).limit(50).to_a
  end

  def queue_stats
    alive = SolidQueue::Process.where("last_heartbeat_at > ?", SolidQueue.process_alive_threshold.ago)
    {
      ready: SolidQueue::ReadyExecution.count,
      scheduled: SolidQueue::ScheduledExecution.count,
      running: SolidQueue::ClaimedExecution.count,
      failed: SolidQueue::FailedExecution.count,
      processes: alive.order(:kind).map { |p| { kind: p.kind, pid: p.pid, last_heartbeat_at: p.last_heartbeat_at.utc.iso8601 } }
    }
  end
end
