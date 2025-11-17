/*
 * Cache Demo - Linux Page Cache Hit/Miss Performance Comparison
 *
 * This program demonstrates the performance difference between page cache hits
 * and misses by reading files with and without dropping the page cache.
 * Useful for understanding the impact of caching on I/O performance.
 *
 * Author: Samuel Matildes (Linux I/O Training)
 * Git repo: github.com/samatild/linux-io-tracing-demos
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage:\n"
        "  %s --hit  [-b <KB>] <file>\n"
        "  %s --miss [-b <KB>] <file>\n"
        "Options:\n"
        "  --hit           Read file twice; second pass shows page-cache hit\n"
        "  --miss          Drop caches before reading (requires root)\n"
        "  -b <KB>         Block size in KiB (default 1024 = 1 MiB)\n",
        prog, prog);
    exit(1);
}

static void read_file(int fd, size_t bs) {
    char *buf = NULL;
    size_t bytes = bs * 1024;
    if (bytes == 0) bytes = 1024 * 1024; // fallback to 1 MiB
    buf = (char*)malloc(bytes);
    if (!buf) {
        perror("malloc");
        exit(1);
    }

    // rewind to start
    if (lseek(fd, 0, SEEK_SET) < 0) {
        perror("lseek");
        free(buf);
        exit(1);
    }

    double t0 = now_sec();
    off_t total = 0;
    while (1) {
        ssize_t n = read(fd, buf, bytes);
        if (n < 0) { perror("read"); free(buf); exit(1); }
        if (n == 0) break;
        total += n;
    }
    double t1 = now_sec();

    double mib = total / (1024.0 * 1024.0);
    double secs = (t1 - t0);
    double mbps = secs > 0 ? mib / secs : 0.0;

    printf("Read %.1f MiB in %.3f s (%.1f MiB/s)\n", mib, secs, mbps);
    free(buf);
}

int main(int argc, char *argv[]) {
    if (argc < 3) usage(argv[0]);

    int mode_hit = 0, mode_miss = 0;
    size_t block_kb = 1024;  // 1 MiB default
    const char *file = NULL;

    // Simple arg parse: allow -b anywhere before the file path
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--hit") == 0) {
            mode_hit = 1;
        } else if (strcmp(argv[i], "--miss") == 0) {
            mode_miss = 1;
        } else if (strcmp(argv[i], "-b") == 0 && i + 1 < argc) {
            block_kb = (size_t)strtoul(argv[++i], NULL, 10);
            if (block_kb == 0) block_kb = 1024;
        } else if (argv[i][0] != '-') {
            file = argv[i];
        } else {
            usage(argv[0]);
        }
    }

    if ((!mode_hit && !mode_miss) || !file) usage(argv[0]);

    int fd = open(file, O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }

    // Show basic file info
    struct stat st;
    if (fstat(fd, &st) != 0) { perror("stat"); close(fd); return 1; }
    if (!S_ISREG(st.st_mode)) {
        fprintf(stderr, "Error: %s is not a regular file\n", file);
        close(fd);
        return 1;
    }
    printf("File: %s  Size: %lld bytes  Block: %zu KiB  Mode: %s\n",
           file, (long long)st.st_size, block_kb, mode_hit ? "HIT" : "MISS");

    if (mode_miss) {
        printf("Dropping caches (requires root): sync; echo 3 > /proc/sys/vm/drop_caches\n");
        int rc = system("sync; echo 3 > /proc/sys/vm/drop_caches");
        if (rc != 0) {
            fprintf(stderr, "Warning: drop_caches failed (need root?). Proceeding anyway...\n");
        }
    }

    // First pass
    printf("Pass 1...\n");
    read_file(fd, block_kb);

    if (mode_hit) {
        // Immediate second pass (should be page-cache hits)
        printf("Pass 2 (expected cache hits)...\n");
        read_file(fd, block_kb);
       }

    close(fd);
    return 0;
}
