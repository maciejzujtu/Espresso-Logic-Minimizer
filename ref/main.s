// =================================================== //
// main.s — Entry point for Espresso Logic Minimizer   //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

// -- TIOCGETA
.equ TIOCGETA_LO,   0x7413
.equ TIOCGETA_HI,   0x4048

.globl _main
.align 2

.text
_main:
    sub     sp, sp,  #128
    stp     x29, x30, [sp, #112]
    add     x29, sp, #112

    // if argc > 1, reject file arguments
    cmp     w0, #1
    b.gt    .Larg_err

    // isatty(STDIN) via ioctl — succeed = terminal → error
    mov     x0, STDIN
    movz    x1, TIOCGETA_LO
    movk    x1, TIOCGETA_HI, lsl #16
    add     x2, sp, #32                  // termios buffer on stack
    syscall SYS_IOCTL_LO, SYS_IOCTL_HI
    b.cc    .Ltty_err                    // carry clear = success = tty

.Lread_loop:
    mov     x0, STDIN
    adrp    x1, file_buf@PAGE
    add     x1, x1, file_buf@PAGEOFF
    mov     x2, FILE_BUF_SIZE
    syscall SYS_READ_LO, SYS_READ_HI
    b.cs    .Ldone
    cbz     x0, .Ldone

    mov     x2, x0
    mov     x0, STDOUT
    adrp    x1, file_buf@PAGE
    add     x1, x1, file_buf@PAGEOFF
    syscall SYS_WRITE_LO, SYS_WRITE_HI

    b       .Lread_loop

.Larg_err:
    mov     x2, usage_len
    b       .Lprint_err

.Ltty_err:
    mov     x2, usage_len

.Lprint_err:
    mov     x0, STDOUT
    adrp    x1, usage@PAGE
    add     x1, x1, usage@PAGEOFF
    syscall SYS_WRITE_LO, SYS_WRITE_HI
    mov     w0, #1
    b       .Lexit

.Ldone:
    mov     w0, #0

.Lexit:
    ldp     x29, x30, [sp, #112]
    add     sp, sp, #128

    syscall SYS_EXIT_LO, SYS_EXIT_HI

.data
.align 3
usage:
    .asciz  "usage: ./main < file\n"
    .equ    usage_len, . - usage

.bss
.align 3
file_buf:
    .space  FILE_BUF_SIZE
