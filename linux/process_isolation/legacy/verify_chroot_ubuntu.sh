#!/bin/bash
set -e
set -x

# 0. Preparation
sudo apt update && sudo apt install -y busybox-static procps util-linux strace

export ROOT=/lab/chroot/rootfs
sudo mkdir -p "$ROOT"

# 1. Theory (no action)

# 2. Build minimal rootfs
sudo install -d -m 0755 "$ROOT"/{bin,sbin,etc,proc,sys,dev,usr/bin,usr/sbin,root,tmp,var/{log,run,lib},home}
sudo chmod 1777 "$ROOT"/tmp

sudo cp /bin/busybox "$ROOT"/bin/
cd "$ROOT"/bin
sudo ln -sf busybox sh
sudo ln -sf busybox ash
sudo ln -sf busybox ls
sudo ln -sf busybox cat
sudo ln -sf busybox echo
sudo ln -sf busybox ps
sudo ln -sf busybox mount
sudo ln -sf busybox uname
sudo ln -sf busybox vi

# Base files in /etc
echo "root:x:0:0:root:/root:/bin/sh" | sudo tee "$ROOT"/etc/passwd
echo "root:x:0:" | sudo tee "$ROOT"/etc/group
echo "chroot-lab" | sudo tee "$ROOT"/etc/hostname
echo "127.0.0.1   localhost" | sudo tee "$ROOT"/etc/hosts
echo "127.0.1.1   chroot-lab" | sudo tee -a "$ROOT"/etc/hosts
sudo cp /etc/resolv.conf "$ROOT"/etc/resolv.conf

# 3. Connect pseudo-FS
sudo mount --rbind /dev  "$ROOT"/dev
sudo mount --make-rslave "$ROOT"/dev
sudo mount -t proc  proc  "$ROOT"/proc
sudo mount -t sysfs sys   "$ROOT"/sys

# Check
mount | egrep "$ROOT/(dev|proc|sys)"

# 4. Enter chroot and check isolation
sudo chroot "$ROOT" /bin/sh -c '
echo "Inside PID: $$"
ps | head -n 5
cat /etc/hostname
hostname
cat /proc/net/dev | head -n 5
'

# 5. Escape demonstration
# Note: I'll run this as a script inside chroot
cat << 'EOF' | sudo tee "$ROOT"/escape.sh
#!/bin/sh
echo "Escape attempt..."
readlink -f /proc/1/root
ls /proc/1/root | head
# The following would start a new shell, so we just run a command to prove access
chroot /proc/1/root /bin/sh -c "hostname; cat /etc/os-release | grep PRETTY_NAME"
EOF
sudo chmod +x "$ROOT"/escape.sh
sudo chroot "$ROOT" /bin/sh /escape.sh

# 6. Unprivileged user
sudo chroot --userspec=65534:65534 "$ROOT" /bin/sh -c 'id; hostname chroot-lab-2 || echo "EPERM as expected"'

# 7. Namespaces: PID/UTS/MNT
sudo unshare --pid --uts --mount --fork \
  --mount-proc="$ROOT/proc" \
  chroot "$ROOT" /bin/sh -c '
echo "PID inside: $$"
hostname chroot-ns
hostname
ps
'

# 8. Cgroups v2
# We need to make sure systemd-run works.
# On some systems, we might need to mount cgroup2 manually if not present.
sudo systemd-run -p MemoryMax=256M -p CPUQuota=25% -t \
  chroot "$ROOT" /bin/sh -c '
mount -t cgroup2 none /sys/fs/cgroup || true
CG=$(cut -d: -f3 /proc/self/cgroup)
echo "Cgroup path: $CG"
cat "/sys/fs/cgroup${CG}/memory.max" || echo "Failed to read memory.max"
cat "/sys/fs/cgroup${CG}/cpu.max" || echo "Failed to read cpu.max"
'

# 9. Strace
sudo strace -e chroot chroot "$ROOT" /bin/sh -c 'echo strace-ok'

# Cleanup (optional, but good for testing)
# We will do cleanup manually or leave it for the user to see results.
# sudo umount -l "$ROOT"/proc
# sudo umount -l "$ROOT"/sys
# sudo umount -l "$ROOT"/dev
