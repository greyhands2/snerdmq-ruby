<div align="center">
  <h1>💎 SnerdMQ Ruby SDK</h1>
  <p>A zero-config, C-speed background job queue for Ruby. Ditch Redis and Sidekiq for lightweight, persistent background jobs.</p>

  [![Gem Version](https://badge.fury.io/rb/snerdmq.svg)](https://badge.fury.io/rb/snerdmq)
</div>

This is the official Ruby SDK wrapper for **SnerdMQ**. It handles all JSON-RPC communication and `IO.popen` orchestration so you can write lightning-fast background jobs without managing any external databases like Redis or Postgres.

## ✨ Features
- **Ditch Sidekiq & Redis**: Gives your Ruby apps persistent state, automatic retries, and dead-letter queues right out of the box with zero external infrastructure.
- **Zero Rust Required**: Our gem installation script automatically downloads the pre-compiled C-speed Rust binary for your OS.
- **Thread Safe**: Uses native Ruby `Thread`s and `Mutex` locks to orchestrate I/O without blocking your main event loop.

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

# 4. Enqueue a job from anywhere in your codebase
queue.enqueue(
  task_id: "email-123",
  task_type: "send_email",
  data: { "to" => "john@wick.com", "subject" => "Continental Update" },
  max_retries: 3,
  retry_after_hours: 0.0
)

# Keep main thread alive
sleep
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
