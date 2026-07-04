# strace-summary Samples

Sample output from `strace -c` syscall summary statistics.

- `basic.txt` - Five syscalls (read, write, open, close, fstat) with errors on open
- `complex.txt` - Eight syscalls with futex, mmap, mprotect and higher call counts
- `minimal.txt` - Two syscalls (read, write) with zero errors
