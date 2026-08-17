<div align="center">
  <img src="./assets/Designer-9.png" height="120" alt="SnerdMQ Ruby Logo" />
  <h1>💎 SnerdMQ Ruby SDK v0.3.1</h1>
  <p>A zero-config, C-speed background job queue for Ruby. Ditch Redis and Sidekiq for lightweight, persistent background jobs.</p>

  [![Gem Version](https://badge.fury.io/rb/snerdmq.svg)](https://badge.fury.io/rb/snerdmq)
</div>

This is the official Ruby SDK wrapper for **SnerdMQ**. It handles all JSON-RPC communication and `IO.popen` orchestration so you can write lightning-fast background jobs without managing any external databases like Redis or Postgres.

## ✨ v0.3.1 AI Features
- **Smart API Rate-Limiting**: Natively tracks `rate_limit_group` execution velocity to prevent 429 "Too Many Requests" API errors.
- **Payload-Hashing Deduplication**: Automatically computes cryptographic hashes to drop duplicate tasks instantly.
- **Dynamic Float Prioritization**: A native Binary Max-Heap bypasses standard FIFO rules for high urgency tasks.
- **Ditch Sidekiq & Redis**: Gives your Ruby apps persistent state, automatic retries, and dead-letter queues right out of the box with zero external infrastructure.
- **Zero Rust Required**: Our gem installation script automatically downloads the pre-compiled C-speed Rust binary for your OS.
- **Thread Safe**: Uses native Ruby `Thread`s and `Mutex` locks to orchestrate I/O without blocking your main event loop.

### ⚙️ Advanced Task Configuration (v0.3.1)
To power complex AI workflows, tasks can now be configured with advanced orchestration parameters:

* **`auto_dedupe` (`true/false`)**: If set to `true`, the daemon computes a cryptographic hash of the `task_type` and `data`. If an identical payload is currently sitting in the queue pending execution, this new task is silently dropped. Excellent for preventing duplicate generative AI requests from trigger-happy users!
* **`urgency_score` (`Float`)**: A value (e.g. `0.99`) used to bypass the standard FIFO queue. SnerdMQ uses a true Binary Max-Heap to continually float tasks with the highest urgency score to the very front of the execution line. Standard tasks default to `0.0`.
* **`rate_limit_group` (`String`)**: A custom string (e.g. `"openai_api"` or `"db_writes"`) that groups tasks together for backpressure control.
* **`max_per_minute` (`Integer`)**: Used in conjunction with `rate_limit_group`. If the queue processes more tasks in this group than the allowed limit within a 60-second rolling window, further tasks in this group are temporarily paused. This natively prevents 429 "Too Many Requests" errors when bursting third-party APIs.
* **`execute_at` (`String` | `Time`)**: A timestamp of when the job should be executed in the future.
* **`cron` (`String`)**: A cron expression (e.g. `"0 * * * *"`) for recurring jobs. Shorthands like `"2h"` or `"10m"` are also supported.
* **`webhook_url` (`String`)**: By providing a webhook URL, SnerdMQ will completely bypass your local Ruby blocks and dispatch the task payload via an HTTP POST request directly to the specified URL.

### 🌐 HTTP Webhooks (Serverless Execution)
You can configure a task to execute externally via an HTTP POST request. By setting a `webhook_url`, the internal background processor will skip any registered handlers (`queue.register_handler`) and directly invoke the HTTP endpoint.

If the HTTP endpoint returns a non-200 status code, it triggers a retry. If it permanently fails (reaches `max_retries`), the Dead Letter Queue event is automatically fired via a final HTTP POST to the same `webhook_url` but with the header `X-SnerdMQ-Event: MaxRetriesReached`.

### 🕒 Cron Jobs vs. Retryable Jobs
When using the new scheduling features, it is important to understand the difference between Cron and Retry behaviors:
> - **A Cron Job** is a *Repeatable Job* that executes again **only after a success**, on a fixed schedule.
> - **A Retryable Job** is a *Recovery Job* that executes again **only after a failure**, attempting to recover using the `retry_after_hours` backoff.
> - **Combined:** If a Cron Job fails, it temporarily uses `retry_after_hours` to retry until it recovers. Once it succeeds, it goes back to ticking on its standard cron schedule!

## 📦 Installation

Installing the SDK is a simple two-step process:

**1. Install the gem:**
```bash
gem install snerdmq
# Or add `gem 'snerdmq'` to your Gemfile
```

**2. Download the Rust Engine:**
Run this script from your terminal immediately after installing the gem. It will fetch the correct highly-optimized SnerdMQ binary for your operating system (macOS/Linux/Windows) and place it securely inside the gem installation directory:
```bash
snerdmq-install
```

---

## ⚡ Quickstart

Using the SDK is incredibly simple. Initialize the queue, register your handler blocks, and start listening!

```ruby
require 'snerdmq'

# 1. Initialize the daemon in the background
queue = Snerdmq::SnerdQueue.new

# 2. Register your background job logic using a standard block
queue.register_handler("send_email") do |data|
  to = data["to"]
  subject = data["subject"]
  puts "Sending email to #{to} with subject: #{subject}..."
  
  # Raise an exception here to automatically trigger SnerdMQ's retry logic!
end

# 3. Start the non-blocking Thread listeners
queue.start_listening
puts "SnerdMQ Ruby SDK is listening for jobs..."

# 4. Enqueue a job from anywhere in your codebase (Now with v0.2.1 AI Features!)
queue.enqueue(
  task_id: "email-123",
  task_type: "send_email",
  data: { "to" => "john@wick.com", "subject" => "Continental Update" },
  max_retries: 3,
  retry_after_hours: 0.0,
  rate_limit_group: "email_api",
  max_per_minute: 100,
  auto_dedupe: true,
  urgency_score: 0.99,
  cron: "1h", # Runs every 1 hour!
  webhook_url: "https://api.example.com/webhook" # Execute via HTTP instead of local handlers
)

# Keep main thread alive
sleep
```

### ☠️ Dead Letter Queue (Handling Permanent Failures)

When a task fails repeatedly and exhausts its `maxRetries`, the SnerdMQ daemon permanently moves it to the Dead Letter Queue. You can hook into this event to alert your team, update your database, or send a Slack message by registering a Max Retry Handler.

```ruby
# 5. Catch tasks that have permanently failed (Dead Letter Queue)
queue.register_max_retry_handler('send_email') do |data|
  puts "Email task failed after all retries! Data: #{data.inspect}"
end
```

---

## 🌍 Advanced: Distributed Scaling

By default, the SDK spins up the Rust daemon which writes the queue to a local file (`.snerdata/tasks/tasks.log`). 

If you have multiple Ruby microservices (or Rails instances) running behind a load balancer and want them to share the exact same queue, simply mount a **Shared Network Drive** (like AWS EFS or NFS) to all of your servers and pass the shared path:

```ruby
require 'snerdmq'

# All of your Ruby servers point to the exact same shared file!
# SnerdMQ's native OS file-locking guarantees zero data corruption.
queue = Snerdmq::SnerdQueue.new(storage_path: "/mnt/aws-efs-shared-drive/snerd_tasks.log")
```

*Built with ❤️ for John Wick tier engineering.*
