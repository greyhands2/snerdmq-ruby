require "minitest/autorun"
require "snerdmq"
require "fileutils"
require "timeout"

class TestSnerdmq < Minitest::Test
  def setup
    # Point to the actual compiled Rust binary in the sibling repository for tests
    ext = RbConfig::CONFIG['host_os'].match?(/mswin|msys|mingw|cygwin|bccwin|wince|emc/) ? '.exe' : ''
    @bin_path = File.expand_path("../../snerdmq/target/debug/snerdmq#{ext}", __dir__)
    @db_path = File.expand_path("../../.snerdata/tasks/tasks.log", __dir__)
    
    FileUtils.rm_f(@db_path)
  end

  def teardown
    FileUtils.rm_f(@db_path)
  end

  def test_full_integration
    queue = Snerdmq::SnerdQueue.new(binary_path: @bin_path)

    job_completed = Queue.new

    queue.register_handler("test_ruby_job") do |data|
      assert_equal "ruby_master", data["user_id"]
      assert_equal "matz", data["message"]
      job_completed.push(true)
    end

    queue.start_listening

    # Give daemon a tiny fraction of a second to boot up
    sleep(0.1)

    queue.enqueue(
      task_id: "ruby-job-1",
      task_type: "test_ruby_job",
      data: { "user_id" => "ruby_master", "message" => "matz" },
      max_retries: 3,
      retry_after_hours: 0.0
    )

    # Wait for the job to complete (timeout after 5 seconds)
    begin
      Timeout.timeout(5) do
        job_completed.pop
      end
    rescue Timeout::Error
      flunk("Test timed out waiting for job completion")
    ensure
      queue.shutdown
    end
  end
end
