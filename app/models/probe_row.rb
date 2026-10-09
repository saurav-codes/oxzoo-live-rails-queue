# Short-lived rows the probe writes, reads back, and deletes.
class ProbeRow < ApplicationRecord
  self.table_name = "zoo_probes"
end
