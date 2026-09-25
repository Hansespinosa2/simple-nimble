if Rails.env.development?
  allowed_hosts = ENV.fetch("SIMPLE_NIMBLE_ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  Rails.application.config.hosts.concat(allowed_hosts)
  Rails.application.config.active_record.dump_schema_after_migration = false
end
