#!/usr/bin/env python3
"""
БИТАЯ версия seccomp_bpf.py для broken/scenario-01.

НАМЕРЕННО не вызывает prctl(PR_SET_NO_NEW_PRIVS) перед установкой фильтра.
От root это сходит с рук (есть CAP_SYS_ADMIN), а от НЕ-root prctl(PR_SET_SECCOMP)
падает с EACCES (errno 13): ядро не даёт непривилегированному процессу ставить
seccomp-фильтр, пока он не зафиксировал no_new_privs.

Usage: seccomp_no_nnp.py <SYSCALL_NR> <CMD> [ARGS...]
"""
import ctypes, ctypes.util, os, struct, sys

def bpf_stmt(code, k):          return struct.pack("HBBI", code, 0, 0, k)
def bpf_jump(code, k, jt, jf):  return struct.pack("HBBI", code, jt, jf, k)

PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2
SECCOMP_RET_KILL_PROCESS = 0x80000000
SECCOMP_RET_ALLOW = 0x7fff0000


class sock_fprog(ctypes.Structure):
    _fields_ = [("len", ctypes.c_ushort), ("filter", ctypes.c_void_p)]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    nr = int(sys.argv[1])
    cmd = sys.argv[2:]
    prog = (bpf_stmt(0x20, 0) +
            bpf_jump(0x15, nr, 0, 1) +
            bpf_stmt(0x06, SECCOMP_RET_KILL_PROCESS) +
            bpf_stmt(0x06, SECCOMP_RET_ALLOW))
    buf = ctypes.create_string_buffer(prog)
    fprog = sock_fprog(len(prog) // 8, ctypes.cast(buf, ctypes.c_void_p).value)
    libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)

    # БАГ: здесь ДОЛЖЕН быть prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) — он пропущен.
    if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(fprog)) != 0:
        e = ctypes.get_errno()
        print("PR_SET_SECCOMP failed: errno=%d (%s)" % (e, os.strerror(e)), file=sys.stderr)
        sys.exit(3)
    os.execvp(cmd[0], cmd)


if __name__ == "__main__":
    main()
