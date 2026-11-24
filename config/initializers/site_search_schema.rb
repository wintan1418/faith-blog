# frozen_string_literal: true

# schema.rb has no room for the search triggers and functions
# (SiteSearch::Schema), so they are installed again whenever a schema is
# loaded: db:schema:load, db:prepare, db:test:prepare and each parallel test
# database. Migrations install them themselves.
ActiveSupport.on_load(:active_record) do
  require "active_record/tasks/database_tasks"

  ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(Module.new do
    def load_schema(db_config, *args, **kwargs)
      super.tap do
        pool = respond_to?(:migration_connection_pool) ? migration_connection_pool : ActiveRecord::Base.connection_pool
        pool.with_connection { |connection| SiteSearch::Schema.install!(connection) }
      end
    end
  end)
end
