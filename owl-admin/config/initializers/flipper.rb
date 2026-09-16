require "flipper"
require "flipper/adapters/active_record"

# Feature flags, stored in this app's own Postgres — no Redis, no external
# service. Toggle from /admin/flipper or the console (see app/services/features.rb
# for the flag names).
Flipper.configure do |config|
  config.default do
    Flipper.new(Flipper::Adapters::ActiveRecord.new)
  end
end
