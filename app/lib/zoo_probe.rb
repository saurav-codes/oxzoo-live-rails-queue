require "securerandom"
require "timeout"

# GET /_zoo/probe: real round trips against every dependency (DESIGN.md).
class ZooProbe
  class Busy < StandardError; end

  LOCAL_LIMIT = 5.0
  PEER_LIMIT = 8.0
  TOTAL_LIMIT = 20.0
  LOCK = Mutex.new

  # One probe at a time per process; a second waits up to 5 s.
  def self.run
    deadline = monotonic + 5
    until LOCK.try_lock
      raise Busy if monotonic > deadline
      sleep 0.05
    end
    begin
      new.run
    ensure
      LOCK.unlock
    end
  end

  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def run
    started = self.class.monotonic
    @deadline = started + TOTAL_LIMIT
    checks = [
      check("postgres", "Postgres write, read, delete", ["DATABASE_URL"], LOCAL_LIMIT) { postgres },
      check("solid-queue", "Solid Queue job run by bin/jobs", ["DATABASE_URL"], LOCAL_LIMIT) { solid_queue },
      check("worker-heartbeat", "Solid Queue worker heartbeat", ["DATABASE_URL"], LOCAL_LIMIT) { heartbeat },
      check("peer:#{Zoo::PEER}", "Signed call to #{Zoo::PEER}", %w[LARAVEL_URL WEBHOOK_SECRET], PEER_LIMIT,
        hops: [Zoo.hop_name, "#{Zoo::PEER}@s2"]) { peer }
    ]
    Zoo.identity.merge(
      ok: checks.all? { |c| c[:ok] },
      ms: elapsed_ms(started),
      at: Time.now.utc.iso8601,
      checks: checks,
      vars: Zoo.vars
    )
  end

  private

  # DATABASE_URL is not required: Rails falls back to config/database.yml
  # locally, and a broken database fails the check itself.
  def check(id, label, env, limit, hops: [Zoo.hop_name], required: env - ["DATABASE_URL"])
    started = self.class.monotonic
    result = { id: id, label: label, ok: false, ms: 0, env: env, hops: hops }
    missing = required.find { |name| Zoo.env(name).nil? }
    if missing
      result[:error] = "#{missing} is not set"
    else
      budget = [limit, @deadline - started].min
      raise Timeout::Error, "probe budget spent" if budget <= 0
      result[:detail] = Timeout.timeout(budget, Timeout::Error, "timeout after #{(budget * 1000).round} ms") { yield }
      result[:ok] = true
    end
    result
  rescue StandardError => e
    result[:error] = e.message.to_s.truncate(300)
    result
  ensure
    result[:ms] = elapsed_ms(started)
  end

  def elapsed_ms(started)
    ((self.class.monotonic - started) * 1000).round
  end

  def postgres
    token = "pg-#{SecureRandom.hex(8)}"
    row = ProbeRow.create!(token: token)
    read = ProbeRow.find_by(token: token)
    raise "read back #{read&.token.inspect}, wrote #{token}" unless read&.id == row.id
    ProbeRow.where(token: token).delete_all
    raise "row still present after delete" if ProbeRow.exists?(token: token)
    "zoo_probes row round trip, server #{ProbeRow.connection.select_value("SHOW server_version")}"
  end

  def solid_queue
    # Leaves a second of the 5 s budget for the cleanup below.
    wait_until = self.class.monotonic + 4
    token = "job-#{SecureRandom.hex(8)}"
    job = ProbeJob.perform_later(token)
    raise "enqueue failed" unless job.successfully_enqueued?
    # The request's query cache would answer the same "no" forever.
    until ProbeRow.uncached { ProbeRow.exists?(token: token) }
      if self.class.monotonic > wait_until
        SolidQueue::Job.where(active_job_id: job.job_id).destroy_all
        raise "no worker ran the probe job within 4000 ms (is bin/jobs running?)"
      end
      sleep 0.1
    end
    "ProbeJob enqueued, run by the worker, its row read back and deleted"
  ensure
    ProbeRow.where(token: token).delete_all if token
  end

  def heartbeat
    alive = SolidQueue::Process.where(kind: "Worker").where("last_heartbeat_at > ?", SolidQueue.process_alive_threshold.ago)
    newest = alive.maximum(:last_heartbeat_at)
    raise "no Solid Queue worker heartbeat in the last #{SolidQueue.process_alive_threshold.to_i} s" unless newest
    "#{alive.count} worker(s), last heartbeat #{(Time.now - newest).round} s ago"
  end

  def peer
    url, key = Zoo.env("LARAVEL_URL"), Zoo.env("WEBHOOK_SECRET")
    response = ZooPeer.call("GET", url, "/_zoo/verify", key: key, timeout: PEER_LIMIT)
    body = response.json || {}
    raise "HTTP #{response.status}: #{body["error"] || "no JSON"}" unless response.status == 200
    raise "name is #{body["name"].inspect}, expected #{Zoo::PEER}" unless body["name"] == Zoo::PEER
    raise "key_fp #{body["key_fp"].inspect} differs from ours #{ZooSig.fp(key)}" unless body["key_fp"] == ZooSig.fp(key)
    unless body["public_url"].to_s.chomp("/") == url.chomp("/")
      raise "public_url #{body["public_url"].inspect} differs from LARAVEL_URL"
    end
    "verified by #{body["verified_by"]} on #{body["server"]}, key_fp #{body["key_fp"]}"
  end
end
