# ox's start passes -b tcp://127.0.0.1:$PORT, so no port is set here.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count
