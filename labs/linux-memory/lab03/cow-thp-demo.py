import os
import sys
import time
import mmap

SIZE = 128 * 1024 * 1024  # 128 MB
print(f"=== Allocating {SIZE // (1024*1024)}MB of anonymous memory ===")

# Create private anonymous mmap
mem = mmap.mmap(-1, SIZE, mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS, mmap.PROT_READ | mmap.PROT_WRITE)

# Fill memory to make it resident (touching memory pages)
print("Touching memory to make all pages resident...")
mem.write(b"A" * SIZE)

def get_rss():
    with open(f"/proc/{os.getpid()}/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    return 0

def get_anon_huge():
    huge = 0
    try:
        with open("/proc/self/smaps") as f:
            for line in f:
                if line.startswith("AnonHugePages:"):
                    huge += int(line.split()[1])
    except Exception:
        pass
    return huge

parent_rss = get_rss()
parent_huge = get_anon_huge()
print(f"Parent PID: {os.getpid()}")
print(f"Parent RSS: {parent_rss} KB (~{parent_rss // 1024} MB)")
print(f"Parent AnonHugePages: {parent_huge} KB (~{parent_huge // 1024} MB)")

print("\nForking child process...")
pid = os.fork()

if pid == 0:
    # Child process
    # Write 1 byte every 64KB (touching 1 page out of every 16 pages)
    print("Child: modifying scattered bytes (1 byte every 64KB)...")
    step = 64 * 1024
    for offset in range(0, SIZE, step):
        mem[offset] = 66  # ASCII for 'B'
    
    child_rss = get_rss()
    child_huge = get_anon_huge()
    print(f"\nChild PID: {os.getpid()}")
    print(f"Child RSS after modification: {child_rss} KB (~{child_rss // 1024} MB)")
    print(f"Child AnonHugePages: {child_huge} KB (~{child_huge // 1024} MB)")
    sys.exit(0)
else:
    # Parent process
    _, status = os.waitpid(pid, 0)
    print("\nChild process exited.")
