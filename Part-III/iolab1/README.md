# I/O Congestion Training Lab 1

This lab demonstrates how I/O contention affects system performance by simulating a "noisy neighbor" process that generates excessive disk I/O.

## Lab Objectives

- Understand how disk I/O contention impacts application performance
- Learn to identify and diagnose I/O bottlenecks
- Observe the difference in upload speeds with and without I/O contention

## How It Works

**BackupJob (Noisy Process)**: A background process that spawns multiple workers, each continuously writing random-sized files (64MB-1GB) to disk with `oflag=direct` to create realistic I/O contention

## Prerequisites

```bash
# Install required tools (optional, for monitoring)
sudo apt-get install sysstat iotop -y
```

## Usage Instructions

**⚠️ IMPORTANT**: Network speed can be a bottleneck!


## Part I - Lab Setup

### Web experience (slow/fast browsing)

These steps set up the "news site" and the background job that will sometimes make it feel slow:

1. **Prepare lab directories**
   - `sudo ./1_prepare_lab.sh`
2. **Start the web server**
   - `sudo ./2_start_webserver.sh`
   - Open `http://localhost:8000` in a browser and browse around to see normal behaviour.
3. **Start the background job**
   - `sudo ./3_start_backupjob.sh`
   - Keep refreshing the page and observe that, in bursts, it now takes much longer to load.

You can stop everything with:

- `sudo ./4_stop_backupjob.sh`
- `sudo ./5_stop_webserver.sh`
- `sudo ./6_cleanup_lab.sh` (optional, removes `/opt/iolab`)

## Part II - Troubleshooting to Find the Culprit

Use these commands while the site is sometimes fast and sometimes slow:

1. **Monitor disk activity**
   - `iostat -xk 1`
   - Watch which disk shows very high utilization and long wait times during slow periods.
2. **Find the process doing heavy disk I/O**
   - `pidstat -d 1`
   - Note the process ID (PID) that is doing the most reads/writes when the disk is busy.
3. **Find the parent process tree**
   - `pstree -ps <pid>`
   - Replace `<pid>` with the PID you found in `pidstat -d`. This shows the most-parent process.
4. **Identify the actual culprit command**
   - `ps -ef | grep <parent_process_id>`
   - Replace `<parent_process_id>` with the parent PID from `pstree`. This reveals which script or binary is responsible for the disk spikes.

Once you have the culprit, explain how it interacts with the web server to slow down page loads.


## Part III - Deep-Dive Questions

### Q1. **Page cache vs direct I/O**
   - Based on the tools you used and the behaviour you observed, was the heavy background job writing directly to disk, or did it primarily use the page cache?
   - Which specific flags, syscalls, or observable metrics led you to that conclusion?

### Easy Answer:  Because dd parameter shows it -> Inspect the backup script to see how it opens files:

 ```bash
grep oflag=direct /opt/iolab/backupjob_runner.sh
# You should see a `dd` command using `oflag=direct` and `conv=fdatasync`, which tells the kernel to bypass the page cache and flush data to disk.
 ```
### Pro Answer: attach `strace` to a backup worker to see the syscalls:
```bash
sudo strace -f -e open,openat,write -p <backup_worker_pid>
### Output with filter 

openat(AT_FDCWD, "/opt/iolab/io_tmp/backupjob_worker_1_1763203243315980308.tmp", O_WRONLY|O_CREAT|O_TRUNC|O_DIRECT, 0666) = 3
```

The `O_DIRECT` flag on this `openat` call is the evidence that the job is issuing direct I/O instead of going through the page cache.

### Answer: the backup job is performing direct, synchronous writes to disk rather than relying on cached writes.

---

### Q2. **I/O wait and scheduling**
   - When the site was slow, what did `iostat -xk 1` show for `await`, `svctm` (if present), and `%util` on the affected device?
   - How do these numbers relate to the kernel’s I/O scheduler behaviour when multiple processes compete for the same block device?

### Answer: High `%util` and high `await` mean the device queue is full and requests are waiting in the scheduler.

The kernel’s I/O scheduler is time-slicing and merging requests from both the web server and the backup job, but the large sequential writes from the backup job dominate the queue and increase latency for the smaller web server I/Os.

---

### Q3. **Process state and blocking**
   - While the background job was in its active phase, what process states did you see for the web server and backup workers (for example in `ps`, `top`, or `pidstat`)?
   - How do states like `D` (uninterruptible sleep) or high I/O wait time explain the latency you saw in the browser?


### Checks
```bash
# Use `pidstat` to capture per-process I/O and wait time:
pidstat -d 1 # (disk I/O) 
pidstat -w 1 # (task switching and iowait).

# Inspect process states directly
ps -o pid,cmd,state,wchan -p <webserver_pid>,<backup_worker_pid>
watch -n1 "ps -o pid,cmd,state,wchan <webserver_pid>"
```
### Answer: When the page is slow, the web server process/threads will frequently be in `D` (uninterruptible sleep) or show high iowait time, indicating they are blocked waiting for disk I/O to complete.
      
---

### Q4. **Throughput vs latency trade-offs* : - If you were designing this for production, what changes (I/O priority, batching, scheduling, filesystem options, or separate volumes) would you propose to reduce user-facing latency without sacrificing backup reliability?

- Possible production mitigations:
   - Lower I/O priority for the backup job: wrap the runner with `ionice -c3` so it yields to interactive workloads.
   - Schedule backups outside peak hours or throttle them (fewer workers, smaller chunks).
   - Place backups on a separate disk they do not compete with the web server’s main data path.


## Lab Architecture

```
┌─────────────────────┐
│  Web Browser        │
└──────────┬──────────┘
           │ HTTP GET
           ▼
┌─────────────────────┐          ┌──────────────────────┐
│  Python Web Server  │          │   BackupJob          │
│  Port 8000          │          │   (3 workers)        │
│                     │          │                      │
│  • Receives         │          │  • Worker 1: 64-1GB  │
│  • Writes with      │◄────────►│  • Worker 2: 64-1GB  │
│    O_SYNC flag      │  I/O     │  • Worker 3: 64-1GB  │
│                     │Contention│                      │
└─────────┬───────────┘          └──────────┬───────────┘
          │                                 │
          │                                 │
          ▼                                 ▼
    ┌──────────────────────────────────────────┐
    │         Disk I/O Subsystem               │
    │  (Limited bandwidth & IOPS)              │
    └──────────────────────────────────────────┘
```

