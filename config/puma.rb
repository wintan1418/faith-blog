# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
# that have no dedicated worker. Without any worker, background jobs never run
# and the AI moderation gate never releases new posts. Set
# SOLID_QUEUE_IN_PUMA=1 to opt in when there is no `bin/jobs` process.
solid_queue_in_puma =
  if ENV.key?("SOLID_QUEUE_IN_PUMA")
    !%w[0 false off no].include?(ENV["SOLID_QUEUE_IN_PUMA"].to_s.downcase)
  else
    # Production on Hatchbox runs a dedicated `bin/jobs` background worker
    # (faith-blog-solid_queue.service). Running a second supervisor inside
    # Puma doubled every queue process (~500MB RAM, 8 extra DB connections)
    # on a shared box, so the plugin is opt-in everywhere now.
    false
  end
plugin :solid_queue if solid_queue_in_puma

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
