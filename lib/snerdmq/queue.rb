require 'json'
require 'thread'

module Snerdmq
  class SnerdQueue
    def initialize(binary_path: nil, storage_path: nil)
      @binary_path = binary_path
      @storage_path = storage_path
      
      if @binary_path.nil?
        ext = RbConfig::CONFIG['host_os'].match?(/mswin|msys|mingw|cygwin|bccwin|wince|emc/) ? '.exe' : ''
        # Assume the binary was downloaded into the gem's bin/ directory via snerdmq-install
        @binary_path = File.expand_path("../../bin/snerdmq#{ext}", __dir__)
      end

      unless File.exist?(@binary_path)
        raise "[Snerd] Binary not found at #{@binary_path}. Ensure it is compiled or run 'snerdmq-install'."
      end

      @handlers = {}
      @handlers_mutex = Mutex.new
      
      @stdin_mutex = Mutex.new
      @shutting_down = false
      @io = nil
      @listener_thread = nil
    end

    def register_handler(task_type, &block)
      @handlers_mutex.synchronize do
        @handlers[task_type] = block
      end

      if @io && !@shutting_down
        send_message({
          action: "register",
          task_type: task_type
        })
      end
    end

    def start_listening
      args = []
      args << @storage_path if @storage_path

      # Open a bidirectional pipe to the Rust daemon
      @io = IO.popen([@binary_path] + args, "r+")

      # Re-register all existing handlers
      @handlers_mutex.synchronize do
        @handlers.keys.each do |task_type|
          send_message({
            action: "register",
            task_type: task_type
          })
        end
      end

      @listener_thread = Thread.new do
        listen_to_stdout
      end
    end

    def enqueue(task_id:, task_type:, data:, max_retries: 3, retry_after_hours: 0.0)
      raise "[Snerd] Cannot enqueue task: Queue is not running. Call start_listening first." if @io.nil? || @shutting_down
      
      send_message({
        action: "enqueue",
        task_id: task_id,
        task_type: task_type,
        task_data: data.to_json,
        max_retries: max_retries,
        retry_after_hours: retry_after_hours
      })
    end

    def shutdown
      @shutting_down = true
      begin
        Process.kill("TERM", @io.pid) if @io && @io.pid
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already dead
      end
      
      @listener_thread.join(2) if @listener_thread
      @io.close if @io && !@io.closed?
    end

    private

    def send_message(msg)
      @stdin_mutex.synchronize do
        return if @shutting_down || @io.nil? || @io.closed?
        @io.puts(msg.to_json)
        @io.flush
      end
    rescue Errno::EPIPE
      # Broken pipe if the daemon died unexpectedly
    end

    def listen_to_stdout
      @io.each_line do |line|
        next if line.strip.empty?

        begin
          msg = JSON.parse(line)
          
          if msg["action"] == "execute"
            # Execute in a short-lived thread so we don't block the stdout listener loop
            Thread.new { handle_execute(msg) }
          elsif msg["action"] == "max_retries_reached"
            warn "[Snerd] Dead Letter Queue: Task #{msg['task_id']} (#{msg['task_type']}) permanently failed."
          end
        rescue JSON::ParserError
          # Ignore malformed stdout lines
        end
      end
    rescue IOError, Errno::EPIPE
      # Normal when shutting down
    end

    def handle_execute(msg)
      task_id = msg["task_id"]
      task_type = msg["task_type"]
      
      raw_data = msg["task_data"]
      task_data = raw_data.is_a?(String) ? JSON.parse(raw_data) : raw_data

      handler = nil
      @handlers_mutex.synchronize do
        handler = @handlers[task_type]
      end

      unless handler
        send_message({
          action: "result",
          task_id: task_id,
          status: "error",
          error_msg: "No handler registered."
        })
        return
      end

      begin
        handler.call(task_data)
        send_message({
          action: "result",
          task_id: task_id,
          status: "success"
        })
      rescue => e
        send_message({
          action: "result",
          task_id: task_id,
          status: "error",
          error_msg: e.message
        })
      end
    end
  end
end
