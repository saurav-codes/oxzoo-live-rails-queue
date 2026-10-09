# One step of a chain trace, kept in this project's own database.
class Hop < ApplicationRecord
  self.table_name = "zoo_hops"

  # Each step is recorded once per trace, so a retried job adds nothing.
  def self.record(trace, step, detail)
    create_or_find_by!(trace: trace, step: step) { |hop| hop.detail = detail.to_s.truncate(200) }
  end

  def as_hop
    { at: created_at.utc.iso8601(3), step: step, detail: detail }
  end
end
