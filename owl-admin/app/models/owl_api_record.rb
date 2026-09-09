# Base class for the handful of tables owl-admin *reads* from owl-api's own
# database (the `owl_api` connection in database.yml). owl-api owns that schema
# and its migrations — Rails treats it as external (`database_tasks: false`), so
# never point a Rails migration at these tables.
class OwlApiRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :owl_api, reading: :owl_api }
end
