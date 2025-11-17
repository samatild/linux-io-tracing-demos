# I/O Delay Lab 2

This lab demonstrates how kernel-level I/O delays can make a simple web
application feel intermittently slow, even when the application code and
infrastructure have not changed.

## Lab Objectives

- Observe how added latency in filesystem calls affects page load times.
- Practice correlating browser symptoms with low-level system metrics.
- Use tools like `iostat`, `pidstat`, and `strace` to reason about I/O paths.

## Part I - Lab Setup

1. Prepare the Lab 2 environment:

   ```bash
   sudo ./1_prepare_lab.sh
   ```

2. Start the Lab 2 web server:

   ```bash
   sudo ./2_start_webserver.sh
   ```

3. Open the Lab 2 page in a browser:

   - URL: `http://localhost:8000`
   - Refresh the page several times and watch the server-side timing panel.

4. When finished, stop and optionally clean up:

   ```bash
   sudo ./5_stop_webserver.sh
   sudo ./6_cleanup_lab.sh   # optional, removes /opt/iolab2
   ```

## Part II - What to Investigate

While Lab 2 is running, there is a kernel module (`io_delayer`) attaching kprobes
to VFS and block-layer functions and adding delay. Use the commands below to
prove that this module is:

1. Loaded and configured.
2. Sitting in the VFS and/or block I/O path.
3. Firing when the Lab 2 web server does I/O.

### 1. Verify the module and its delay settings

From the `io-delayer` directory:

```bash
# Check that the module is loaded
lsmod | grep io_delayer

# Show current VFS and block-layer delays and hook symbol
sudo ./io-delayer-cli status

# Or via sysfs directly
cat /sys/kernel/io_delayer/delay_us
cat /sys/kernel/io_delayer/blk_delay_us
cat /sys/kernel/io_delayer/blk_hook_symbol
```

### 2. Prove that the kprobes are armed on VFS functions

Use ftrace to check that the module’s pre-handlers are present:

```bash
# List filterable functions and grep for io-delayer handlers
cat /sys/kernel/debug/tracing/available_filter_functions | grep io_delayer
```

You should see entries like:

```bash
pre_handler_vfs_read [io_delayer]
pre_handler_vfs_write [io_delayer]
pre_handler_do_sys_open [io_delayer]
```

This confirms that the module has registered handlers right at the VFS layer.

### 3. Watch io-delayer fire while Lab 2 serves requests

1. Set up ftrace to show every probe:


   ```bash
   echo "*" | sudo tee /sys/kernel/debug/tracing/set_ftrace_filter
   
   # Or filter for vfs calls (better)
   echo "*vfs*" | sudo tee /sys/kernel/debug/tracing/set_ftrace_filter
   
     
   echo function | sudo tee /sys/kernel/debug/tracing/current_tracer
   echo 1 | sudo tee /sys/kernel/debug/tracing/tracing_on
   ```

   ```bash
   echo "pre_handler_vfs_read pre_handler_vfs_write pre_handler_do_sys_open" | \
     sudo tee /sys/kernel/debug/tracing/set_ftrace_filter

   echo function | sudo tee /sys/kernel/debug/tracing/current_tracer
   echo 1 | sudo tee /sys/kernel/debug/tracing/tracing_on
   ```

2. Sream the trace, filter python:

   ```bash
   sudo cat /sys/kernel/debug/tracing/trace_pipe | grep python
   ```

   You can now narrow down your search to specific probes that you know hare happening:

      ```bash
   echo "pre_handler_vfs_read pre_handler_vfs_write pre_handler_do_sys_open vfs_read vfs_write do_sys_open" | \
     sudo tee /sys/kernel/debug/tracing/set_ftrace_filter

         python3-4519    [000] .....  1902.967741: vfs_write <-ksys_write
         python3-4519    [000] .....  1902.967741: pre_handler_vfs_write <-kprobe_ftrace_handler
         python3-4519    [000] .....  1902.969196: vfs_fsync_range <-ext4_buffered_write_iter
         python3-4519    [000] .....  1902.984352: vfs_write <-ksys_write
         python3-4519    [000] .....  1902.984352: pre_handler_vfs_write <-kprobe_ftrace_handler
         python3-4519    [000] .....  1902.985818: vfs_fsync_range <-ext4_buffered_write_iter
         python3-4519    [000] .....  1903.002085: vfs_write <-ksys_write
         python3-4519    [000] .....  1903.002085: pre_handler_vfs_write <-kprobe_ftrace_handler

   echo function | sudo tee /sys/kernel/debug/tracing/current_tracer
   echo 1 | sudo tee /sys/kernel/debug/tracing/tracing_on
   ```


3. In another terminal, hit the Lab 2 web server a few times:

   ```bash
   curl -s http://localhost:8000 > /dev/null
   curl -s http://localhost:8000 > /dev/null
   ```

You should see the `pre_handler_*` functions fire for every request. This proves
that the kprobes are on the code path of the Lab 2 web request I/O.

### 4. Correlate userspace syscalls with VFS and io-delayer (Actual troubleshooting for this lab)

1. Find the Lab 2 webserver PID:

   ```bash
   cat /opt/iolab2/http-server.pid
   # or:
   ps -ef | grep "webserver.py" | grep iolab2
   ```

2. Attach `strace` to see its syscalls:

   ```bash
   sudo strace -tt -e trace=open,read,write -p <webserver_pid>
   ```

3. At the same time, trace the VFS layer:

   ```bash
   echo "vfs_read vfs_write do_sys_open" | \
     sudo tee /sys/kernel/debug/tracing/set_ftrace_filter
   echo function | sudo tee /sys/kernel/debug/tracing/current_tracer
   echo 1 | sudo tee /sys/kernel/debug/tracing/tracing_on

   sudo cat /sys/kernel/debug/tracing/trace | \
     grep -E "(vfs_read|vfs_write|do_sys_open)" | tail -40
   ```

Use these outputs to build a full chain:

`browser → webserver syscalls (open/read/write) → vfs_* calls → io_delayer pre_handlers → actual disk I/O`.

### 5. Questions

#### Q1: Is the delay being applied at the VFS layer, the block layer, or both?


#### Q2: Which block-layer symbol is actually hooked on this kernel?
