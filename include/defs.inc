// =================================================== //
// Description:      Variables definitions             //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

// SYSCALL
.equ SYS_EXIT,          0x2000001
.equ SYS_READ,          0x2000003
.equ SYS_WRITE,         0x2000004
.equ SYS_OPEN,          0x2000005
.equ SYS_CLOSE,         0x2000006
.equ SYS_IOCTL,         0x2000036

// STD
.equ STDIN,             0x0000
.equ STDOUT,            0x0001
.equ BUF_SIZE,          1024

// FLAGS
.equ O_RDONLY,          0x0000
.equ O_WRONLY,          0x0001
.equ O_RDWR,            0x0002