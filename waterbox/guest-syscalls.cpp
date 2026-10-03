// guest-syscalls.cpp — syscall gap fillers for the musl guest (M2).
//
// Syscall gaps are normal: each shows up as an ENOSYS crash the first time
// upstream reaches for it (closefrom, clock_getres, getcwd, mkdir, lstat,
// fcntl, sched_getaffinity, ...). Add them here as they appear. M0/M1: empty
// by design — the file exists so M2 has a place to collect them.
